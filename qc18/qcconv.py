"""QCConv2d: conv whose GEMM matrix (qc.structure "hwc" view) is quasi-cyclic (QC).

Weight matrix M[cout, kh*kw*cin_pad], columns (kh, kw, cin), cin zero-padded to a multiple of b, tiled
into b x b blocks; block (r, c) = sum_s v[r, c, s] P_s with v[r, c] in the discrete set V:
  signed:   v in {-1,0,1}^b with <= 2 nonzeros   (|V| = 1 + 2b + 4 C(b,2))
  unsigned: v in {0,1}^b    with <= 2 nonzeros   (|V| = 1 + b + C(b,2))

Latent theta[R, Cb, b] (one real per block row, block col, shift).  Hard projection (exact):
  v = hard(theta) = argmax_{v in V} score(v),  score(v) = <theta, v> - (alpha_r / 2) |v|_0
  alpha_r (detached) = mean over the blocks of row r of the mean of the block's top-2 |theta|.
  Closed form: rank shifts by |theta| (signed) / theta (unsigned) with a stable sort (lowest shift wins
  ties), keep the top 2 whose key > alpha_r / 2, value sign(theta) (signed) / 1 (unsigned).
Backward (estimator):
  ste:   dv/dtheta = I.
  gibbs: p(v) ∝ exp(score(v) / (tau alpha_r)) over all of V;  grad_theta = Cov_p(v) g / (tau alpha_r),
         the exact Jacobian (transposed) of the smoothed mean E_p[v](theta).  tau is a buffer (trainer sets it).
The hard coefficients are stored in the buffer `v` (refresh()); in eval mode the layer uses `v`, so the
checkpoint holds exactly the network that was evaluated (no device/precision-dependent re-derivation).
mode="dense": ordinary conv weight.  No conv bias (a BatchNorm follows).
relax (diagnostic only; the result is NOT a QC network, real weights): "circ" = forward uses theta itself (real
block-circulant, all b shifts); "top2" = forward uses theta on the top-2 |theta| shifts per block (exact mask,
zeros elsewhere, gradient straight through the mask).  Train and eval use the relaxed weights; `v` still holds
hard(theta) so the flip rate stays comparable.
homotopy (training forward only; eval always uses the stored hard `v`): while the layer's `h_on` flag is set,
  gibbs: forward = Gibbs mean E_p[v](theta) (p as above, temperature buffer tau), exact autograd Jacobian;
  ramp:  forward = (1 - lam) r + lam (hard(theta) + STE), r = top2 mask * theta / alpha_r (exact gradient through r,
         mask and alpha_r detached), lam = buffer `hlam`.
The trainer sets tau / hlam each step and clears `h_on` when the homotopy ends -> forward = hard + STE.
"""
import itertools

import torch
import torch.nn as nn
import torch.nn.functional as F

from qc.structure import cin_pad, expand, from_matrix, to_matrix


def vset(b, signed, dtype=torch.float32):
    """All v in V as rows [K, b]: zero, one nonzero, two nonzeros at distinct shifts."""
    vals = (1, -1) if signed else (1,)
    rows = [[0] * b]
    for i in range(b):
        for s in vals:
            r = [0] * b
            r[i] = s
            rows.append(r)
    for i, j in itertools.combinations(range(b), 2):
        for si in vals:
            for sj in vals:
                r = [0] * b
                r[i], r[j] = si, sj
                rows.append(r)
    return torch.tensor(rows, dtype=dtype)


def row_alpha(theta):
    """alpha[R, 1, 1]: per block row, mean over blocks of the mean of the block's top-2 |theta| (detached)."""
    t = theta.detach().abs()
    top = t.topk(min(2, t.shape[-1]), dim=-1).values.mean(-1)          # [R, Cb]
    return top.mean(-1)[:, None, None].clamp(min=1e-12)


@torch.no_grad()
def sphere_(theta):
    """In place: rescale each block row's latents theta[r] to unit RMS (norm sqrt(Cb*b)).  hard() is invariant
    to positive per-row rescaling (alpha_r scales with theta_r), so the network is unchanged."""
    n = theta[0].numel()
    theta.mul_(n ** 0.5 / theta.flatten(1).norm(dim=1).clamp(min=1e-12)[:, None, None])
    return theta


def hard(theta, alpha, signed):
    """Exact argmax over V of <theta, v> - alpha/2 |v|_0 per block (see module doc)."""
    t = theta.detach()
    key = t.abs() if signed else t
    idx = key.sort(dim=-1, descending=True, stable=True).indices[..., :2]
    keep = key.gather(-1, idx) > alpha / 2
    val = torch.sign(t.gather(-1, idx)) if signed else torch.ones_like(keep, dtype=t.dtype)
    return torch.zeros_like(t).scatter(-1, idx, keep.to(t.dtype) * val)


def top2(theta):
    """theta on the top-2 |theta| shifts per block (stable sort), zeros elsewhere; gradient identity."""
    t = theta.detach()
    idx = t.abs().sort(dim=-1, descending=True, stable=True).indices[..., :2]
    m = torch.zeros_like(t).scatter(-1, idx, 1.0)
    return t * m + (theta - t)


def gibbs_mean(theta, alpha, tau, V):
    """E_p[v] per block, p(v) ∝ exp(score(v) / (tau alpha)) over all of V (alpha detached); differentiable."""
    nnz = (V != 0).sum(1).to(theta.dtype)
    p = torch.softmax((theta @ V.T - 0.5 * alpha * nnz) / (tau * alpha), dim=-1)
    return p @ V


def ramp(theta, alpha, lam, signed):
    """(1 - lam) top2(theta) / alpha + lam (hard(theta) + STE)."""
    t = theta.detach()
    idx = t.abs().sort(dim=-1, descending=True, stable=True).indices[..., :2]
    r = theta * torch.zeros_like(t).scatter(-1, idx, 1.0) / alpha
    return (1 - lam) * r + lam * (hard(theta, alpha, signed) + (theta - t))


def gibbs_vjp(theta, alpha, tau, V, g, chunk=1 << 22):
    """Cov_p(v) g / (tau alpha) per block, p(v) ∝ exp((<theta,v> - alpha/2 |v|_0) / (tau alpha)).
    theta, g [R, Cb, b]; alpha [R, 1, 1]; V [K, b].  Chunked over blocks to bound the [N, K] buffers."""
    b, K = theta.shape[-1], V.shape[0]
    th, gg = theta.reshape(-1, b), g.reshape(-1, b)
    a = alpha.expand(theta.shape[:-1] + (1,)).reshape(-1, 1)
    nnz = (V != 0).sum(1).to(theta.dtype)
    out = torch.empty_like(th)
    n = max(1, chunk // K)
    for i in range(0, th.shape[0], n):
        t, gc, ac = th[i:i + n], gg[i:i + n], a[i:i + n]
        T = tau * ac
        p = torch.softmax((t @ V.T - 0.5 * ac * nnz) / T, dim=-1)       # [n, K]
        pvg = p * (gc @ V.T)                                              # p(v) <v, g>
        out[i:i + n] = (pvg @ V - (p @ V) * pvg.sum(-1, keepdim=True)) / T
    return out.reshape(theta.shape)


class GibbsProject(torch.autograd.Function):
    """Forward: hard(theta) (exact).  Backward: Gibbs-smoothed Jacobian (gibbs_vjp)."""

    @staticmethod
    def forward(ctx, theta, alpha, tau, V, signed):
        ctx.save_for_backward(theta, alpha, tau, V)
        return hard(theta, alpha, signed)

    @staticmethod
    def backward(ctx, g):
        theta, alpha, tau, V = ctx.saved_tensors
        with torch.autocast(g.device.type, enabled=False):
            return gibbs_vjp(theta.float(), alpha.float(), tau.float(), V.float(), g.float()).to(theta.dtype), \
                None, None, None, None


class QCConv2d(nn.Module):
    def __init__(self, cin, cout, k, stride=1, padding=0, mode="dense", b=8, estimator="ste", tau=1.0, relax="none",
                 qinit_scale="unit", homotopy="none"):
        super().__init__()
        self.cin, self.cout, self.k, self.stride, self.padding = cin, cout, k, stride, padding
        self.mode, self.b, self.estimator, self.relax = mode, b, estimator, relax
        self.homotopy, self.h_on = homotopy, homotopy != "none"
        W = torch.empty(cout, cin, k, k)
        nn.init.kaiming_normal_(W, nonlinearity="relu")
        if mode == "dense":
            self.weight = nn.Parameter(W)
            return
        assert mode in ("signed", "unsigned") and estimator in ("ste", "gibbs") and cout % b == 0
        assert relax in ("none", "circ", "top2") and homotopy in ("none", "gibbs", "ramp")
        assert homotopy == "none" or (relax == "none" and estimator == "ste")
        self.signed = mode == "signed"
        theta = self.circulant_projection(W, b)
        if qinit_scale == "unit":                                        # unit std (scale is free: BN follows)
            theta = theta / theta.std()
        else:                                                            # "dense": keep the Kaiming-projected scale
            assert qinit_scale == "dense"
        self.theta = nn.Parameter(theta)
        self.register_buffer("v", hard(theta, row_alpha(theta), self.signed))
        self.register_buffer("tau", torch.tensor(float(tau)))
        self.register_buffer("hlam", torch.tensor(0.0), persistent=False)
        self.register_buffer("V", vset(b, self.signed), persistent=False)

    @staticmethod
    def circulant_projection(W, b):
        """Least-squares projection onto block-circulant: theta[r, c, s] = mean of the s-th cyclic diagonal."""
        M = to_matrix(W, b)
        R, Cb = M.shape[0] // b, M.shape[1] // b
        B = M.reshape(R, b, Cb, b).permute(0, 2, 1, 3)                  # [R, Cb, i, j]
        i = torch.arange(b)
        return B[:, :, i[None, :], (i[None, :] + i[:, None]) % b].mean(-1)   # [R, Cb, s]

    @torch.no_grad()
    def refresh(self):
        """Store the hard coefficients of the current theta (used in eval mode and saved in checkpoints)."""
        self.v.copy_(hard(self.theta, row_alpha(self.theta), self.signed))

    def coef(self):
        """Coefficients [R, Cb, b] of the forward pass: exact hard values, estimator gradient (training)."""
        if self.relax == "circ":
            return self.theta
        if self.relax == "top2":
            return top2(self.theta)
        if not self.training:
            return self.v
        th = self.theta
        alpha = row_alpha(th)
        if self.h_on and self.homotopy == "gibbs":
            return gibbs_mean(th, alpha, self.tau, self.V)
        if self.h_on and self.homotopy == "ramp":
            return ramp(th, alpha, self.hlam, self.signed)
        if self.estimator == "ste":
            return hard(th, alpha, self.signed) + (th - th.detach())
        return GibbsProject.apply(th, alpha, self.tau, self.V, self.signed)

    def matrix(self):
        """Stored hard QC matrix [cout, k*k*cin_pad] incl. the padded input-channel columns."""
        return expand(self.v, self.b)

    def get_weight(self):
        if self.mode == "dense":
            return self.weight
        return from_matrix(expand(self.coef(), self.b), self.cin, self.k, self.b)

    def forward(self, x):
        with torch.autocast(x.device.type, enabled=False):
            w = self.get_weight()
        return F.conv2d(x, w, stride=self.stride, padding=self.padding)

    def extra_repr(self):
        s = f"{self.cin}, {self.cout}, k={self.k}, stride={self.stride}, mode={self.mode}"
        if self.mode == "dense":
            return s
        s += f", b={self.b}, cin_pad={cin_pad(self.cin, self.b)}, {self.estimator}"
        s += "" if self.homotopy == "none" else f", homotopy={self.homotopy}"
        return s if self.relax == "none" else s + f", relax={self.relax}"
