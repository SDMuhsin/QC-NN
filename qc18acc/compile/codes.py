"""Weight codes and wide memory words (ARCH.md "Weight code", Appendix).

Block code (10 b): two 5-b terms, term j at bits [5j+4 : 5j] = {k[2:0], t[1:0]} (k = shift, t = trit:
00 = 0, 01 = +1, 11 = -1; 10 is illegal).  Canonical order: the nonzero terms in ascending shift, then zero
terms (0, 00).  Block output y[i] = t1 x[(i + k1) mod 8] + t2 x[(i + k2) mod 8], i.e. block = sum_s c[s] P_s
(qc.structure, P_s[i, j] = 1 iff j = (i + s) mod 8) with c[k1] = t1, c[k2] = t2.

Wide words (80-b weight, 72-b param) are numpy uint64 arrays [n, 2] = (bits 63:0, bits 127:64).
Weight word: code of column g at bits [10g+9 : 10g].  FC word: int8 W8[j, 8cb + lane] at bits [8 lane + 7 : 8 lane].
Param word: bias int32 [31:0], m0 [62:32], sh [68:63], d [69], spare [71:70] = 0.
"""
import numpy as np

B = 8
CODE_BITS, WEIGHT_BITS, PARAM_BITS = 10, 80, 72
M64 = (1 << 64) - 1


# ---- block codes ---------------------------------------------------------------------------------------------
def encode(C):
    """Coefficients C[..., 8] (entries -1/0/1, <= 2 nonzero) -> canonical codes [...] (int64)."""
    C = np.asarray(C, dtype=np.int64)
    nz = C != 0
    assert C.shape[-1] == B and np.isin(C, (-1, 0, 1)).all() and (nz.sum(-1) <= 2).all(), "not a QC block"
    order = np.argsort(~nz, axis=-1, kind="stable")[..., :2]        # nonzero shifts first, ascending
    t = np.take_along_axis(C, order, -1)
    k = np.where(t != 0, order, 0)
    term = (k << 2) | (t & 3)                                        # trit: 0 -> 00, +1 -> 01, -1 -> 11
    return term[..., 0] | (term[..., 1] << 5)


def decode(codes):
    """codes [...] -> (k [..., 2], t [..., 2]); asserts every code is legal and canonical."""
    codes = np.asarray(codes, dtype=np.int64)
    term = np.stack([codes & 31, (codes >> 5) & 31], -1)
    k, tb = term >> 2, term & 3
    assert (codes >> 10 == 0).all() and (tb != 2).all(), "illegal trit"
    t = np.where(tb == 3, -1, tb)
    assert np.array_equal(encode(coefs(k, t)), codes), "non-canonical code"
    return k, t


def coefs(k, t):
    """(k, t) [..., 2] -> coefficient vectors c[..., 8] (sum of the two terms)."""
    c = np.zeros(k.shape[:-1] + (B,), dtype=np.int64)
    for j in range(2):
        np.put_along_axis(c, k[..., j:j + 1], np.take_along_axis(c, k[..., j:j + 1], -1) + t[..., j:j + 1], -1)
    return c


def valid_blocks():
    """All 129 legal signed b=8 blocks: [129, 8]."""
    out = [np.zeros(B, np.int64)]
    for s1 in range(B):
        for t1 in (1, -1):
            v = np.zeros(B, np.int64)
            v[s1] = t1
            out.append(v)
            for s2 in range(s1 + 1, B):
                for t2 in (1, -1):
                    w = v.copy()
                    w[s2] = t2
                    out.append(w)
    return np.stack(out)


# ---- wide words ----------------------------------------------------------------------------------------------
def to_wide(ints):
    """Python ints (< 2^128) -> uint64 [n, 2]."""
    return np.array([[v & M64, v >> 64] for v in ints], dtype=np.uint64).reshape(-1, 2)


def from_wide(w):
    return [int(lo) | (int(hi) << 64) for lo, hi in np.asarray(w, dtype=np.uint64)]


def field(w, pos, n):
    """Bits [pos+n-1 : pos] of wide words w [..., 2] -> int64 (unsigned, n <= 32 here)."""
    lo, hi = w[..., 0], w[..., 1]
    mask = np.uint64((1 << n) - 1)
    if pos >= 64:
        v = hi >> np.uint64(pos - 64)
    elif pos + n <= 64:
        v = lo >> np.uint64(pos)
    else:
        v = (lo >> np.uint64(pos)) | (hi << np.uint64(64 - pos))
    return (v & mask).astype(np.int64)


def sext(v, n):
    return np.where(v >= 1 << (n - 1), v - (1 << n), v)


def weight_word(codes8):
    """8 codes (column g = output group g) -> one 80-b word (int)."""
    return sum(int(c) << (CODE_BITS * g) for g, c in enumerate(codes8))


def word_codes(w):
    """Weight words [n, 2] -> codes [n, 8]."""
    return np.stack([field(w, CODE_BITS * g, CODE_BITS) for g in range(8)], -1)


def fc_word(w8):
    """8 int8 FC weights (lane order) -> one 80-b word (int), upper 16 b zero."""
    return sum((int(v) & 255) << (8 * i) for i, v in enumerate(w8))


def fc_weights(w):
    """FC words [n, 2] -> int8 lanes [n, 8]."""
    return np.stack([sext(field(w, 8 * i, 8), 8) for i in range(8)], -1)


def param_word(bias, m0, sh, d):
    assert -2 ** 31 <= bias < 2 ** 31 and 0 <= m0 < 2 ** 31 and 0 <= sh < 64 and d in (0, 1)
    return (int(bias) & 0xFFFFFFFF) | (int(m0) << 32) | (int(sh) << 63) | (int(d) << 69)


def param_fields(w):
    """Param words [n, 2] -> (bias, m0, sh, d) int64 arrays."""
    return sext(field(w, 0, 32), 32), field(w, 32, 31), field(w, 63, 6), field(w, 69, 1)
