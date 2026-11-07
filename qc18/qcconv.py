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


def hard(theta, alpha, signed):
    """Exact argmax over V of <theta, v> - alpha/2 |v|_0 per block (see module doc)."""
    t = theta.detach()
    key = t.abs() if signed else t
    idx = key.sort(dim=-1, descending=True, stable=True).indices[..., :2]
    keep = key.gather(-1, idx) > alpha / 2
    val = torch.sign(t.gather(-1, idx)) if signed else torch.ones_like(keep, dtype=t.dtype)
    return torch.zeros_like(t).scatter(-1, idx, keep.to(t.dtype) * val)


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
    def __init__(self, cin, cout, k, stride=1, padding=0, mode="dense", b=8, estimator="ste", tau=1.0):
        super().__init__()
        self.cin, self.cout, self.k, self.stride, self.padding = cin, cout, k, stride, padding
        self.mode, self.b, self.estimator = mode, b, estimator
        W = torch.empty(cout, cin, k, k)
        nn.init.kaiming_normal_(W, nonlinearity="relu")
        if mode == "dense":
            self.weight = nn.Parameter(W)
            return
        assert mode in ("signed", "unsigned") and estimator in ("ste", "gibbs") and cout % b == 0
        self.signed = mode == "signed"
        theta = self.circulant_projection(W, b)
        theta = theta / theta.std()                                      # unit std (scale is free: BN follows)
        self.theta = nn.Parameter(theta)
        self.register_buffer("v", hard(theta, row_alpha(theta), self.signed))
        self.register_buffer("tau", torch.tensor(float(tau)))
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
        if not self.training:
            return self.v
        th = self.theta
        alpha = row_alpha(th)
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
        return s if self.mode == "dense" else s + f", b={self.b}, cin_pad={cin_pad(self.cin, self.b)}, {self.estimator}"
