"""Block-6 int8 maps in the stream buffer S (R2b, supply config C of results/supply.md; hw/rtl/qb_act2.sv): slice-major
layout, S addresses, and the writer-side (plane, chunk) zero flags.  Imports compile/layout.py (binary maps unchanged).

S = 32 lanes x rf_2p 256 x 128 (results/mem.md, ARCH v1.2); one *S word* = the 16 lane-words of one address on lanes
0..15 = 2048 b (lane l = word bits 128 l .. 128 l + 127).  The block-6 int8 maps use lanes 0..15 only, at addresses
S_BASE.. (disjoint from the block-6 r / s stream, which uses lanes 16..31, see results/r2b.md):

    map  source of     words (index)                       bits inside the word                         S address
    HQ   b6.c1         (plane, chunk g)   8 x 8 = 64       pos = 256 y + 32 x + (c & 31), g = c >> 5     HQ_A  + 8 pl + g
    HQD  b6.sc         (plane, half h)    8 x 2 = 16       even pixels (2 oy, 2 ox) of HQ, t = c >> 5:   HQD_A + 2 pl + h
                                                           h = t >> 2, pos = 512 (t & 3) + 128 oy + 32 ox + (c & 31)
    Z    b6.c2         (plane, chunk >> 2) 8 x 4 = 32      pos = 512 (g & 3) + 128 y + 32 x + (c & 31)  Z_A   + 4 pl + (g >> 2)

A (plane, chunk) *slice* is 2048 b (HQ: one word), 4096 b (HQD: the plane's two words; b6.sc has one chunk) or 512 b
(Z: a quarter word).  Zero flags (one per slice, set = slice has a 1 bit; written by the producer as it writes S:
HQ / HQD by the hm jobs, Z by the b6.c1 drain; store: 64 + 8 + 128 = 200 set-only flops in qb_act2, cleared per
bank by the producer before its first write).  The slice is executed by the array iff its flag is set (= the
dataflow skip rule: every 3x3 pad-1 / 1x1 stride-2 patch of block 6 covers the whole (decimated) slice).

    s_words(t, kind)        dataflow entries of the source buffer (one image, plane-major) -> {S address: 2048 bits}
    flags(t, kind)          [n] uint8 slice flags in bank order (HQ: 8 pl + g, HQD: pl, Z: 16 pl + g)
    from_words(w, kind)     inverse of s_words
"""
import numpy as np

from . import layout as LY  # noqa: F401  (binary maps: compile/layout.py)

WORD = 2048
HQ_A, HQD_A, Z_A = 128, 192, 208          # S addresses (lanes 0..15), 112 words = 224 kb
GEOM = {"hq": (8, 8, 256), "hqd": (8, 8, 256), "z": (4, 4, 512)}   # H, W, C of the source map
BASE = {"hq": HQ_A, "hqd": HQD_A, "z": Z_A}
NFLAG = {"hq": 64, "hqd": 8, "z": 128}


def _planes(t, kind):
    H, W, C = GEOM[kind]
    return np.asarray(t).reshape(-1)[:8 * H * W * C].reshape(8, H, W, C).astype(np.uint8)


def s_words(t, kind):
    m = _planes(t, kind)
    out = {}
    if kind == "hq":                                  # [pl, y, x, g, 32] -> word (pl, g): [y, x, 32]
        w = m.reshape(8, 8, 8, 8, 32).transpose(0, 3, 1, 2, 4).reshape(64, WORD)
    elif kind == "hqd":                               # even pixels [pl, oy, ox, t, 32] -> [pl, h, t&3, oy, ox, 32]
        d = m[:, ::2, ::2].reshape(8, 4, 4, 2, 4, 32).transpose(0, 3, 4, 1, 2, 5)
        w = d.reshape(16, WORD)
    else:                                             # [pl, y, x, q, g&3, 32] -> [pl, q, g&3, y, x, 32]
        w = m.reshape(8, 4, 4, 4, 4, 32).transpose(0, 3, 4, 1, 2, 5).reshape(32, WORD)
    for i in range(len(w)):
        out[BASE[kind] + i] = w[i]
    return out


def from_words(words, kind):
    n = {"hq": 64, "hqd": 16, "z": 32}[kind]
    w = np.stack([words[BASE[kind] + i] for i in range(n)])
    if kind == "hq":
        return w.reshape(8, 8, 8, 8, 32).transpose(0, 2, 3, 1, 4).reshape(-1)
    if kind == "hqd":
        return w.reshape(8, 2, 4, 4, 4, 32).transpose(0, 3, 4, 1, 2, 5).reshape(-1)    # [pl, oy, ox, C] even pixels
    return w.reshape(8, 4, 4, 4, 4, 32).transpose(0, 3, 4, 1, 2, 5).reshape(-1)


def flags(t, kind):
    m = _planes(t, kind)
    if kind == "hq":
        return m.reshape(8, 8, 8, 8, 32).any((1, 2, 4)).reshape(-1).astype(np.uint8)
    if kind == "hqd":
        return m[:, ::2, ::2].reshape(8, -1).any(1).astype(np.uint8)
    return m.reshape(8, 4, 4, 16, 32).any((1, 2, 4)).reshape(-1).astype(np.uint8)


def _selftest():
    rng = np.random.default_rng(1)
    for kind in ("hq", "hqd", "z"):
        H, W, C = GEOM[kind]
        t = (rng.random(8 * H * W * C) < 0.02).astype(np.uint8)
        ws = s_words(t, kind)
        m = _planes(t, kind)
        if kind == "hqd":
            assert np.array_equal(from_words(ws, kind), m[:, ::2, ::2].reshape(-1))
        else:
            assert np.array_equal(from_words(ws, kind), t)
        f = flags(t, kind)
        for _ in range(300):                                      # spot checks of the bit position formulas
            pl, c = int(rng.integers(8)), int(rng.integers(C))
            if kind == "hqd":
                oy, ox = (int(v) for v in rng.integers(0, 4, 2))
                tt = c >> 5
                a, pos, v = HQD_A + 2 * pl + (tt >> 2), 512 * (tt & 3) + 128 * oy + 32 * ox + (c & 31), m[pl, 2 * oy, 2 * ox, c]
            else:
                y, x = (int(v) for v in rng.integers(0, H, 2))
                g = c >> 5
                if kind == "hq":
                    a, pos = HQ_A + 8 * pl + g, 256 * y + 32 * x + (c & 31)
                else:
                    a, pos = Z_A + 4 * pl + (g >> 2), 512 * (g & 3) + 128 * y + 32 * x + (c & 31)
                v = m[pl, y, x, c]
            assert ws[a][pos] == v
        # flags == executed-slice rule on the words
        if kind == "hq":
            assert np.array_equal(f, np.array([ws[HQ_A + i].any() for i in range(64)], np.uint8))
        elif kind == "hqd":
            assert np.array_equal(f, np.array([ws[HQD_A + 2 * p].any() | ws[HQD_A + 2 * p + 1].any() for p in range(8)], np.uint8))
        else:
            assert np.array_equal(f, np.array([ws[Z_A + i // 4][512 * (i % 4):512 * (i % 4) + 512].any() for i in range(128)], np.uint8))
    return "layout_s self-test PASS"


if __name__ == "__main__":
    print(_selftest())
