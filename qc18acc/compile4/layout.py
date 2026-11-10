"""v4 (16 pixel rows) activation layout, AGU, kw window and drain pixel pairing (ARCH.md "v4").

Activation word = 128 b pair word as v3 (channel groups 2j lo / 2j + 1 hi of one pixel; uint64 [..., 2] = (lo, hi)).
index(j, y, x) = j * H * W + pix(y, x) (v2 pix: raster / phase) as v3, but bank = index mod 16 and address =
base + (index >> 4): a buffer is 16 banks x 256 words of 128 b (one 256 x 128 macro per bank) = 64 KiB, flat
position bank * 256 + address.  Output tile = 16 consecutive raster output indexes o0..o0+15 (o0 16-aligned); for a
tap (kh, kw, j) row p reads index o0 + p + c(kh, kw, j) (the v2 tap offset on pairs), i.e. 16 consecutive indexes =
16 distinct banks in both layouts.  kw window: 16 raw slots, slot j = index B + j, the v2 shift / held / read rule.
Drain: the shadow chains of a column are split by row bit 1 (chain A = rows 0, 1, 4, 5, 8, 9, 12, 13, chain B =
rows + 2); each drain read takes pixel a (chain A head) and pixel b = a + 2 (chain B head), which lie in different
banks for every layout and map size of the network (`pair_rows`, checked by `drain_conflicts`).
"""
import copy

import numpy as np

from qc18acc.compile.layout import coords, index, kw_order, lanes_to_words, pix, tap_offset, words_to_lanes  # noqa: F401
from qc18acc.compile3.layout import _groups, join16, split16  # noqa: F401

ROWS, BANKS, DEPTH = 16, 16, 256
LB = 4                                                    # log2(BANKS)


def cinp(cin8):
    return (cin8 + 1) // 2


def pairs(p):
    q = copy.copy(p)
    q.cin8 = cinp(p.cin8)
    return q


def flat(idx, base):
    return (idx & (BANKS - 1)) * DEPTH + base + (idx >> LB)


def tap_order(k, stride, cin8):
    """Per-tile step sequence = weight word order within an og (unchanged from v3): [(kh, kw, j)]."""
    return [(kh, kw, j) for kh in range(k) for j in range(cinp(cin8)) for kw in kw_order(k, stride)]


def tap_consec(k, stride, cin8):
    return [i > 0 and (stride == 1 or i == 1) for kh in range(k) for j in range(cinp(cin8))
            for i in range(len(kw_order(k, stride)))]


def agu(o0, kh, kw, j, p):
    """Row input indexes [16] and valid mask [16] of tile o0, tap (kh, kw), pair j (p: pass with cin8 = groups)."""
    o = o0 + np.arange(ROWS)
    yo, xo = coords(o, p.Wout)
    yi, xi = p.stride * yo + kh - p.pad, p.stride * xo + kw - p.pad
    valid = (yi >= 0) & (yi < p.Hin) & (xi >= 0) & (xi < p.Win)
    return o + tap_offset(p.in_lay, p.stride, p.pad, kh, kw, j, p.Hin, p.Win, p.Hout, p.Wout), valid


def gather_plan(p):
    """Whole-pass AGU: flat positions [P, S] and valid mask [P, S], S = k*k*cinp steps in tap order."""
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
    """16-slot kw window over one og (the og loop repeats it): base [T, S], lane [T, S, 16], shift [S], read [T, S, 16]
    (slot j = index B + j; shift = structural rule, asserted equal to B == previous B + 1; held = shift ? have >> 1 : 0,
    read = lane & ~held, have = held | lane)."""
    T = p.Hout * p.Wout // ROWS
    taps = tap_order(p.k, p.stride, p.cin8)
    shift = np.array(tap_consec(p.k, p.stride, p.cin8))
    base, lane = np.zeros((T, len(taps)), np.int64), np.zeros((T, len(taps), ROWS), bool)
    for s, (kh, kw, j) in enumerate(taps):
        for t in range(T):
            idx, v = agu(ROWS * t, kh, kw, j, p)
            base[t, s], lane[t, s] = idx[0], v
    seq = base.reshape(-1)
    inc = np.concatenate([[False], seq[1:] == seq[:-1] + 1])
    assert np.array_equal(inc, np.tile(shift, T)), f"{getattr(p, 'name', '?')}: structural shift rule != index rule"
    read = np.zeros_like(lane)
    have = np.zeros(T, np.int64)
    bits = 1 << np.arange(ROWS)
    for s in range(len(taps)):
        held = (have >> 1) if shift[s] else np.zeros(T, np.int64)
        m = (lane[:, s] * bits).sum(1)
        r = m & ~held
        read[:, s] = (r[:, None] >> np.arange(ROWS)) & 1
        have = held | m
    return dict(base=base, lane=lane, shift=shift, read=read)


def act_reads(p):
    """Array act-bank reads (128-b words) of a whole pass (all og): (v4 window, one per valid lane)."""
    w = window_plan(p)
    return int(w["read"].sum()) * p.cout64, int(w["lane"].sum()) * p.cout64


def tensor_positions(layout, base, npairs, H, W):
    j, y, x = np.meshgrid(np.arange(npairs), np.arange(H), np.arange(W), indexing="ij")
    return flat(index(layout, j, y, x, H, W), base)


def write_tensor(buf, t, layout, base):
    """int8 map t [..., C, H, W] -> buffer words buf [..., 4096, 2] (in place)."""
    H, W = t.shape[-2:]
    g = _groups(np.asarray(t))
    pos = tensor_positions(layout, base, g.shape[-5], H, W)
    for h in range(2):
        buf[..., pos, h] = lanes_to_words(g[..., h, :, :, :])


def read_tensor(buf, layout, base, C, H, W):
    G = C // 8
    pos = tensor_positions(layout, base, (G + 1) // 2, H, W)
    lanes = words_to_lanes(np.ascontiguousarray(buf[..., pos, :]))
    lanes = np.moveaxis(lanes, -2, -4)
    g = lanes.reshape(lanes.shape[:-5] + (-1,) + lanes.shape[-3:])[..., :G, :, :, :]
    return np.moveaxis(g, -1, -3).reshape(buf.shape[:-2] + (C, H, W))


# ---- drain pixel pairing ----------------------------------------------------------------------------------------
CHAIN_A = [0, 1, 4, 5, 8, 9, 12, 13]                     # rows with bit 1 = 0, in chain order (head first)


def pair_rows():
    """Drain read r = 0..31 (chain position c = r >> 2, output pair m = r & 3) -> (row a, row b = a + 2, m)."""
    return [(CHAIN_A[r >> 2], CHAIN_A[r >> 2] + 2, r & 3) for r in range(32)]


def drain_conflicts(layout, H, W, npairs_out):
    """Number of drain reads whose two pixels (rows a, a + 2 of a tile) map to the same bank in `layout` (0 = OK)."""
    bad = 0
    for o0 in range(0, H * W, ROWS):
        for a, b, m in pair_rows():
            for j in range(npairs_out):
                ia = index(layout, j, *coords(o0 + a, W), H, W)
                ib = index(layout, j, *coords(o0 + b, W), H, W)
                bad += int((ia - ib) % BANKS == 0)
    return bad
