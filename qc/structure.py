"""Quasi-cyclic (QC) matrix structure of conv weights.  No training code here.

A conv weight W[cout, cin, kh, kw] is viewed as the GEMM matrix M[cout, kh*kw*cin_pad]:
  view="hwc" (default): column order (kh, kw, cin), so a b x b block lies within one kernel tap;
  view="chw":           column order (cin, kh, kw).
cin is zero-padded to a multiple of b (conv0: 3 -> 8 for b=8, as the hardware pads conv0).

M is QC with block size b if every b x b block is zero or the sum of at most two DISTINCT
cyclically shifted identities P_s (P_s[i, j] = 1 iff j == (i + s) mod b).  A block is described
by its coefficient vector c[s] (s = 0..b-1): block = sum_s c[s] P_s.  Entries 0/1 is the strict
definition; signed=True also allows c[s] = -1 (entries -1/0/1).
"""
import numpy as np
import torch


def cin_pad(cin, b):
    return -(-cin // b) * b


def perms(b, device=None, dtype=torch.float32):
    """P[s, i, j] = 1 iff j == (i + s) mod b."""
    i = torch.arange(b, device=device)
    return (i[None, None, :] == (i[None, :, None] + i[:, None, None]) % b).to(dtype)


def to_matrix(W, b, view="hwc"):
    """W[cout, cin, k, k] (torch or numpy) -> M[cout, ncols] with cin zero-padded to a multiple of b."""
    W = torch.as_tensor(W)
    cout, cin, kh, kw = W.shape
    W = torch.nn.functional.pad(W, (0, 0, 0, 0, 0, cin_pad(cin, b) - cin))
    W = W.permute(0, 2, 3, 1) if view == "hwc" else W
    return W.reshape(cout, -1)


def from_matrix(M, cin, k, b, view="hwc"):
    """Inverse of to_matrix: M[cout, ncols] -> W[cout, cin, k, k] (padded input channels dropped)."""
    M = torch.as_tensor(M)
    cp = cin_pad(cin, b)
    if view == "hwc":
        W = M.reshape(M.shape[0], k, k, cp).permute(0, 3, 1, 2)
    else:
        W = M.reshape(M.shape[0], cp, k, k)
    return W[:, :cin].contiguous()


def expand(C, b):
    """Coefficients C[R, Cb, b] (block row, block col, shift) -> matrix [R*b, Cb*b]."""
    C = torch.as_tensor(C)
    R, Cb, _ = C.shape
    blocks = torch.einsum("rcs,sij->rcij", C, perms(b, C.device, C.dtype))
    return blocks.permute(0, 2, 1, 3).reshape(R * b, Cb * b)


def decompose(M, b, signed=False):
    """Matrix -> coefficients C[R, Cb, b] (int8) with expand(C, b) == M.  Raises ValueError if M is not QC."""
    M = np.asarray(torch.as_tensor(M).detach().cpu().double())
    rows, cols = M.shape
    if rows % b or cols % b:
        raise ValueError(f"shape {M.shape} not a multiple of b={b}")
    B = M.reshape(rows // b, b, cols // b, b).transpose(0, 2, 1, 3)    # [R, Cb, i, j]
    i = np.arange(b)
    diag = B[:, :, i[None, :], (i[None, :] + i[:, None]) % b]           # [R, Cb, s, i] = B[i, (i+s)%b]
    c = diag[..., 0]
    allowed = (-1, 0, 1) if signed else (0, 1)
    for r, q in zip(*np.nonzero((diag != c[..., None]).any(-1))):
        raise ValueError(f"block ({r},{q}): a cyclic diagonal is not constant")
    for r, q in zip(*np.nonzero(~np.isin(c, allowed).all(-1))):
        raise ValueError(f"block ({r},{q}): coefficient not in {allowed}: {c[r, q]}")
    for r, q in zip(*np.nonzero((c != 0).sum(-1) > 2)):
        raise ValueError(f"block ({r},{q}): {(c[r, q] != 0).sum()} shifts > 2")
    return c.astype(np.int8)


def shift_list(C):
    """C[R, Cb, b] -> {(r, c): [(shift, coef), ...]} for the non-zero blocks."""
    C = np.asarray(C)
    return {(r, q): [(int(s), int(C[r, q, s])) for s in np.nonzero(C[r, q])[0]]
            for r, q in zip(*np.nonzero(C.any(-1)))}
