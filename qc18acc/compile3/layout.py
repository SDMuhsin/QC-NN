"""v3 (Kb = 2) activation layout, AGU and kw window (ARCH.md "v3").

Activation word = 128 b = channel groups 2j (low half, bits 63:0) and 2j + 1 (high half) of one pixel, held as
uint64 [..., 2] = (lo, hi).  Pair plane j of a C-channel int8 tensor = groups (2j, 2j + 1); an odd group count is
padded with a zero group (the stem input: 3 channels + 5 zero lanes in the low half, a zero high half).
index(j, y, x) = j * H * W + pix(y, x) (v2 pix: raster / phase), bank = index mod 8, address = base + (index >> 3);
a buffer is 8 banks x 512 words of 128 b (two 512 x 64 macros per bank, lo / hi) = 64 KiB, flat position
bank * 512 + address.  The AGU rule and the kw window are v2's with cb -> pair j (the tap offset c(kh, kw, j) uses
j * H * W), so the v2 functions run on a pair view of the pass (`pairs(p)`: cin8 -> cinp = ceil(cin8 / 2)).
Tap order per tile: kh, j, kw (stride-2 3x3: kw 0, 2, 1).
int16 R (RAW16 / RES_R): pair j of output groups (2j, 2j + 1) -> pair planes 2j (low bytes of both groups) and
2j + 1 (high bytes): the int8 group-plane order of the 2C-channel byte tensor is lo(2j), lo(2j + 1), hi(2j), hi(2j + 1).
"""
import copy

import numpy as np

from qc18acc.compile.layout import agu, coords, index, kw_order, lanes_to_words, tap_offset, words_to_lanes  # noqa: F401
from qc18acc.compile import layout as L2

BANKS, DEPTH = 8, 512


def cinp(cin8):
    return (cin8 + 1) // 2


def pairs(p):
    """Pass / descriptor view with cin8 := number of input pairs (v2 AGU / window functions then index pairs)."""
    q = copy.copy(p)
    q.cin8 = cinp(p.cin8)
    return q


def flat(idx, base):
    return (idx & 7) * DEPTH + base + (idx >> 3)


def tap_order(k, stride, cin8):
    """Per-tile step sequence = v3 weight word order within an og: [(kh, kw, j)], kh outer, pair j, kw inner."""
    return L2.tap_order(k, stride, cinp(cin8))


def gather_plan(p):
    """Whole-pass AGU on pairs: flat positions [P, S] and valid mask [P, S], S = k*k*cinp steps in tap order."""
    P = p.Hout * p.Wout
    o = np.arange(P)
    yo, xo = coords(o, p.Wout)
    pos, val = [], []
    for kh, kw, j in tap_order(p.k, p.stride, p.cin8):
        yi, xi = p.stride * yo + kh - p.pad, p.stride * xo + kw - p.pad
        v = (yi >= 0) & (yi < p.Hin) & (xi >= 0) & (xi < p.Win)
        idx = o + tap_offset(p.in_lay, p.stride, p.pad, kh, kw, j, p.Hin, p.Win, p.Hout, p.Wout)
        pos.append(np.where(v, flat(np.where(v, idx, 0), p.in_base), 0))
        val.append(v)
    return np.stack(pos, 1), np.stack(val, 1)


def window_plan(p):
    return L2.window_plan(pairs(p))


def act_reads(p):
    """Array act-bank reads (128-b words, both halves) of a pass: (v3 window, one per valid lane)."""
    return L2.act_reads(pairs(p))


def tensor_positions(layout, base, npairs, H, W):
    j, y, x = np.meshgrid(np.arange(npairs), np.arange(H), np.arange(W), indexing="ij")
    return flat(index(layout, j, y, x, H, W), base)


def _groups(t):
    """int map [..., C, H, W] -> int8 lanes [..., pairs, 2, H, W, 8] (zero group appended if C / 8 is odd)."""
    C, H, W = t.shape[-3:]
    g = t.reshape(t.shape[:-3] + (C // 8, 8, H, W))
    if (C // 8) % 2:
        g = np.concatenate([g, np.zeros_like(g[..., :1, :, :, :])], -4)
    g = np.moveaxis(g, -3, -1)                                                     # [..., G, H, W, 8]
    return g.reshape(g.shape[:-4] + (g.shape[-4] // 2, 2) + g.shape[-3:])


def write_tensor(buf, t, layout, base):
    """int8 map t [..., C, H, W] -> buffer words buf [..., 4096, 2] (in place)."""
    H, W = t.shape[-2:]
    g = _groups(np.asarray(t))
    pos = tensor_positions(layout, base, g.shape[-5], H, W)
    for h in range(2):
        buf[..., pos, h] = lanes_to_words(g[..., h, :, :, :])


def read_tensor(buf, layout, base, C, H, W):
    """buffer words [..., 4096, 2] -> int8 map [..., C, H, W]."""
    G = C // 8
    pos = tensor_positions(layout, base, (G + 1) // 2, H, W)
    lanes = words_to_lanes(np.ascontiguousarray(buf[..., pos, :]))                # [..., j, H, W, 2, 8]
    lanes = np.moveaxis(lanes, -2, -4)                                             # [..., j, 2, H, W, 8]
    g = lanes.reshape(lanes.shape[:-5] + (-1,) + lanes.shape[-3:])[..., :G, :, :, :]
    return np.moveaxis(g, -1, -3).reshape(buf.shape[:-2] + (C, H, W))


def split16(R):
    """int16 R [..., C, H, W] -> int8 byte planes [..., 2C, H, W], group order lo(2j), lo(2j+1), hi(2j), hi(2j+1)."""
    R = np.asarray(R, dtype=np.int64)
    C, H, W = R.shape[-3:]
    assert C % 16 == 0
    lo, hi = (R & 255).astype(np.uint8).view(np.int8), (R >> 8).astype(np.int8)
    g = lambda a: a.reshape(a.shape[:-3] + (C // 16, 1, 16, H, W))
    return np.concatenate([g(lo), g(hi)], -4).reshape(R.shape[:-3] + (2 * C, H, W))


def join16(planes):
    C2, H, W = planes.shape[-3:]
    p = np.asarray(planes).reshape(planes.shape[:-3] + (C2 // 32, 2, 16, H, W))
    lo, hi = p[..., 0, :, :, :].astype(np.int64) & 255, p[..., 1, :, :, :].astype(np.int64)
    return (hi * 256 + lo).reshape(planes.shape[:-3] + (C2 // 2, H, W))
