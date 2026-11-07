"""Bit-exact numpy model of the QC-GeMMX array (ARCH.md "Datapath").

Per fire (M = 8 pixels m, K = 8 input channels, N = 8 output channels n):
  x_k = a_k - subtraction_a (9 b);  per row and input pair p: s_p = x_2p + x_2p+1, d_p = x_2p - x_2p+1
  column decoder (block j = n/2, p; code (a, b)): even n -> (ca, cb) = (a, b), odd n -> (b, a);
    ca, cb both nonzero: ca == cb -> ca*s_p, ca == -cb -> ca*d_p;  only ca -> ca*x_2p;
    only cb -> cb*x_2p+1;  none -> 0
  tile (m, n): sum_p sel  (12 b), accumulated over K fires on top of C in int32 (wraps).
"""
import numpy as np

from .codec import trit_decode

SEL_NAMES = ("zero", "x_even", "x_odd", "sum", "diff")


def decode_selects(codes):
    """codes uint64 [...] -> (which, sign) int64 [..., 8 n, 4 p]; which indexes SEL_NAMES."""
    codes = np.asarray(codes, dtype=np.uint64)
    nib = (codes[..., None] >> (np.arange(16, dtype=np.uint64) * np.uint64(4))) & np.uint64(15)
    nib = nib.astype(np.int64).reshape(codes.shape + (4, 4))             # [..., j, p]
    a, b = trit_decode(nib), trit_decode(nib >> 2)
    ca = np.stack([a, b], axis=-2).reshape(codes.shape + (8, 4))         # n = 2j + (0: a, 1: b)
    cb = np.stack([b, a], axis=-2).reshape(codes.shape + (8, 4))
    both = (ca != 0) & (cb != 0)
    which = np.where(both, np.where(ca == cb, 3, 4), np.where(ca != 0, 1, np.where(cb != 0, 2, 0)))
    sign = np.where(ca != 0, ca, cb)
    return which, sign


def qc_array(X, codes, stats=None):
    """X int [T, K, 8 m, 8 k] (= a - subtraction_a), codes uint64 [T, K] -> sum over the K fires,
    int64 [T, 8 m, 8 n] (add C and wrap to int32 outside).  stats: dict, counters are added:
      fires, selects (= fires * 256 tile muxes), nz_code (muxes with a nonzero code),
      nz_data (muxes whose selected value is nonzero), by_kind[5] (muxes per select kind)."""
    X = np.asarray(X, dtype=np.int64)
    x0, x1 = X[..., 0::2], X[..., 1::2]                                  # [T, K, m, p]
    cand = np.stack([np.zeros_like(x0), x0, x1, x0 + x1, x0 - x1], axis=-1)  # [T, K, m, p, 5]
    which, sign = decode_selects(codes)                                  # [T, K, n, p]
    T_, K_ = which.shape[:2]
    idx = np.broadcast_to(which[:, :, None, :, :, None], (T_, K_, 8, 8, 4, 1))
    c = np.broadcast_to(cand[:, :, :, None, :, :], (T_, K_, 8, 8, 4, 5))
    val = np.take_along_axis(c, idx, axis=-1)[..., 0] * sign[:, :, None]  # [T, K, m, n, p]
    if stats is not None:
        f = T_ * K_
        stats["fires"] = stats.get("fires", 0) + f
        stats["selects"] = stats.get("selects", 0) + f * 256
        stats["nz_code"] = stats.get("nz_code", 0) + 8 * int((which != 0).sum())
        stats["nz_data"] = stats.get("nz_data", 0) + int((val != 0).sum())
        bk = np.bincount(which.reshape(-1), minlength=5) * 8
        stats["by_kind"] = stats.get("by_kind", np.zeros(5, np.int64)) + bk
    return val.sum(axis=(1, 4))
