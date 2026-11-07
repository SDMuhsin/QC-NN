"""QCConv2d: conv whose GEMM matrix (qc.structure view) is quasi-cyclic.

Block-circulant parametrisation: one real parameter per (block row, block col, shift).  Two methods:

method="staged" (default): `coef` are real block-circulant coefficients (CirCNN-like), hardened by
  qc.train's schedule through two buffers:
    mask[R, Cb, b]  shifts still allowed (all ones in stage A, pruned to top-k per block in stage B);
    lam             0 = real coefficients, 1 = hard QC coefficients (ramped in stage C).
  soft = mask * coef / alpha_r   (alpha_r = mean |kept coef| of block row r, a per-output-channel scale
                                  that the following BatchNorm absorbs)
  hard = mask * q(coef):  unsigned q = 1 if coef > thr*alpha_r else 0;
                          signed   q = sign(coef) if |coef| > thr*alpha_r else 0.
  Forward value: soft + lam*(hard - soft) (exactly `hard` at lam = 1); gradient: that of soft (STE).
  unsigned keeps coef >= 0 (projected in qc.train).
method="ste" (legacy supermask): `scores`, top-k per block, hard coefficients with a straight-through
  gradient from the first step (unsigned: 1 for the top-k scores > 0; signed: sign of the top-k by |score|).
method="qat": same `coef`/`mask`/quantizer as staged, but hard from the first step (lam = 1): forward value
  = hard (exact), backward = d/dcoef of coef/alpha_r for every shift (pruned ones too, so the top-k mask,
  recomputed by qc.train each step until it is frozen, can change), zeroed where |coef| > clip*alpha_r
  if clip > 0 (clipped-identity STE).  Latent coef trained with Adam (qc.train).  With lam = 0
  (qc.train --soft) the forward value is the real, masked mask * coef / alpha_r instead.
mode="dense": plain conv weight (baseline).
Keras 'same' padding is applied inside the layer; no bias (a BatchNorm follows).
"""
import torch
import torch.nn as nn
import torch.nn.functional as F

from nn.model.resnet8 import keras_same_pad

from .structure import cin_pad, expand, from_matrix, to_matrix

SCORE_STD = 0.01   # initial legacy score scale (scores are trained with Adam, see train.py)


def topk_idx(key, k):
    """Indices of the k largest along the last dim; deterministic tie-break (lowest index) on any device."""
    return key.sort(dim=-1, descending=True, stable=True).indices[..., :k]


class QCConv2d(nn.Module):
    def __init__(self, cin, cout, k, stride, b=8, mode="unsigned", topk=2, view="hwc", method="staged", thr=0.0):
        super().__init__()
        self.cin, self.cout, self.k, self.stride = cin, cout, k, stride
        self.b, self.mode, self.topk, self.view, self.method, self.thr = b, mode, topk, view, method, thr
        if mode == "dense":
            self.weight = nn.Parameter(torch.empty(cout, cin, k, k))
            nn.init.kaiming_normal_(self.weight, nonlinearity="relu")
            return
        assert mode in ("unsigned", "signed") and method in ("staged", "ste", "qat") and cout % b == 0
        shape = (cout // b, k * k * cin_pad(cin, b) // b, b)
        if method == "ste":
            self.scores = nn.Parameter(torch.randn(shape) * SCORE_STD)
            return
        fan_in = k * k * cin
        c = torch.randn(shape) * (2.0 / fan_in) ** 0.5            # Kaiming scale of the expanded matrix
        self.coef = nn.Parameter(c.abs() if mode == "unsigned" else c)
        self.register_buffer("mask", torch.ones(shape))
        self.register_buffer("lam", torch.zeros(()))
        self.clip = 0.0      # qat STE clip (training only; does not change the forward value)

    # ---- staged method ----
    # The hard coefficients must not depend on device/dtype (verify runs fp64 on CPU, training fp32 on GPU):
    # the quantizer is evaluated in fp64 and top-k uses a stable sort (lowest shift wins exact ties).
    def _alpha(self, c):
        c, m = c.double(), self.mask.double()
        if self.mode == "unsigned":     # qat latent coef may be < 0 (-> 0); staged coef are >= 0 anyway
            c = c.clamp(min=0)
        return ((c.abs() * m).sum((1, 2), keepdim=True) / m.sum((1, 2), keepdim=True).clamp(min=1)).clamp(min=1e-12)

    def _hard(self, c, alpha):
        t, cd = self.thr * alpha, c.double()
        q = (cd > t).double() if self.mode == "unsigned" else torch.sign(cd) * (cd.abs() > t)
        return (self.mask * q.to(c.dtype))

    @torch.no_grad()
    def prune_to(self, k):
        """Stage B: keep the k largest kept coefficients per block (nested: pruned shifts stay pruned)."""
        key = (self.coef if self.mode == "unsigned" else self.coef.abs()).masked_fill(self.mask == 0, -float("inf"))
        idx = topk_idx(key, k)
        self.mask.copy_(torch.zeros_like(self.mask).scatter_(-1, idx, 1.0) * self.mask)

    @torch.no_grad()
    def topk_mask(self):
        """qat: mask = top-k shifts per block of the current latent coef (not nested)."""
        key = self.coef if self.mode == "unsigned" else self.coef.abs()
        self.mask.copy_(torch.zeros_like(self.mask).scatter_(-1, topk_idx(key, min(self.topk, self.b)), 1.0))

    # ---- common ----
    def hard_coef(self):
        """Exact coefficients C[R, Cb, b] in {0,1} (unsigned) or {-1,0,1} (signed)."""
        if self.method in ("staged", "qat"):
            c = self.coef.detach()
            return self._hard(c, self._alpha(c))
        s = self.scores
        key = s if self.mode == "unsigned" else s.abs()
        idx = topk_idx(key, self.topk)
        keep = torch.zeros_like(s).scatter_(-1, idx, 1.0)
        return keep * (s > 0) if self.mode == "unsigned" else keep * torch.sign(s)

    def matrix(self):
        """Full QC matrix [cout, k*k*cin_pad] incl. the padded input-channel columns (exact at lam = 1)."""
        return expand(self.hard_coef(), self.b)

    def weight_eff(self):
        if self.mode == "dense":
            return self.weight
        if self.method == "staged":
            c = self.coef
            alpha = self._alpha(c.detach())
            soft = self.mask * c / alpha.to(c.dtype)
            hard = self._hard(c.detach(), alpha)
            val = torch.where(self.lam >= 1, hard, soft.detach() + self.lam * (hard - soft.detach()))
            coef = val + (soft - soft.detach())
        elif self.method == "qat":
            c = self.coef
            alpha = self._alpha(c.detach())
            hard = self._hard(c.detach(), alpha)
            g = c / alpha.to(c.dtype)
            if self.clip > 0:
                g = g * (c.detach().abs() <= self.clip * alpha.to(c.dtype))
            coef = torch.where(self.lam >= 1, hard + (g - g.detach()),   # exact hard value, STE gradient
                               self.mask * g)                           # lam < 1 (--soft): real, masked
        else:
            s = self.scores
            coef = self.hard_coef().detach() + (s - s.detach())    # straight-through estimator (exact value)
        return from_matrix(expand(coef, self.b), self.cin, self.k, self.b, self.view)

    def forward(self, x):
        return F.conv2d(keras_same_pad(x, self.k, self.stride), self.weight_eff(), stride=self.stride)

    @torch.no_grad()
    def init_from_dense(self, W):
        """Least-squares projection of a dense weight onto block-circulant: c_s = mean of the s-th cyclic
        block diagonal (staged: used as the real coefficients; ste: scores rescaled to SCORE_STD)."""
        M = to_matrix(torch.as_tensor(W, dtype=torch.float32), self.b, self.view)
        p = self.scores if self.method == "ste" else self.coef
        R, Cb, b = p.shape
        B = M.reshape(R, b, Cb, b).permute(0, 2, 1, 3)
        i = torch.arange(b)
        d = B[:, :, i[None, :], (i[None, :] + i[:, None]) % b].mean(-1).to(p.device)   # [R, Cb, s]
        if self.method != "ste":
            p.copy_(d.clamp(min=0) if self.mode == "unsigned" else d)
        else:
            p.copy_(d / d.std() * SCORE_STD)
