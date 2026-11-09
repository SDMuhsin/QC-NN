"""Activation map layouts and the AGU rule (ARCH.md "Map layout").

index(cb, y, x) = cb * H * W + pix(y, x);  raster pix = y W + x;  phase pix = ((y&1)*2 + (x&1)) (H/2)(W/2)
+ (y>>1)(W/2) + (x>>1).  Bank = index mod 8, address = base + (index >> 3).  A buffer is 8 banks x 1024 words;
a flat buffer position is bank * 1024 + address.
AGU: output tile = raster output indexes o0..o0+7 (o0 8-aligned); for tap (kh, kw) and input group cb the
lane-i input index is o0 + i + c(kh, kw, cb), a per-tap constant.  Lanes whose input coordinate
(s yo + kh - pad, s xo + kw - pad) is outside the map read zero.
v2 tap order per tile (= weight word order): kh, cb, kw (kw innermost; stride-2 3x3 visits kw 0, 2, 1).
Sliding window (ARCH.md "kw window"): consecutive taps of a (kh, cb) run whose base index o0 + c grows by 1 shift
an 8-word raw window by one lane and read only the words not already held (normally one bank).
"""
import numpy as np

RASTER, PHASE = 0, 1
BANKS, DEPTH = 8, 1024


def pix(layout, y, x, H, W):
    if layout == RASTER:
        return y * W + x
    assert H % 2 == 0 and W % 2 == 0
    return ((y & 1) * 2 + (x & 1)) * (H // 2) * (W // 2) + (y >> 1) * (W // 2) + (x >> 1)


def index(layout, cb, y, x, H, W):
    return cb * H * W + pix(layout, y, x, H, W)


def flat(idx, base):
    """Map index -> flat buffer position bank * 1024 + base + (idx >> 3)."""
    return (idx & 7) * DEPTH + base + (idx >> 3)


def bank_addr(idx, base):
    return idx & 7, base + (idx >> 3)


def tap_offset(layout, stride, pad, kh, kw, cb, Hin, Win, Hout, Wout):
    """c(kh, kw, cb): input index = raster output index + c, for every in-range lane."""
    ey, ex = kh - pad, kw - pad
    if stride == 1:
        assert layout == RASTER and (Hin, Win) == (Hout, Wout), "stride-1 consumer needs raster, same size"
        return cb * Hin * Win + ey * Win + ex
    assert stride == 2 and layout == PHASE and (Hin, Win) == (2 * Hout, 2 * Wout), "stride-2 consumer needs phase"
    ph = (ey & 1) * 2 + (ex & 1)
    return cb * Hin * Win + ph * Hout * Wout + (ey >> 1) * Wout + (ex >> 1)


def coords(o, Wout):
    return o // Wout, o % Wout


def agu(o0, kh, kw, cb, p):
    """Lane input indexes [8] and valid mask [8] for tile o0 of pass p (layout.Geometry-like)."""
    o = o0 + np.arange(8)
    yo, xo = coords(o, p.Wout)
    yi, xi = p.stride * yo + kh - p.pad, p.stride * xo + kw - p.pad
    valid = (yi >= 0) & (yi < p.Hin) & (xi >= 0) & (xi < p.Win)
    return o + tap_offset(p.in_lay, p.stride, p.pad, kh, kw, cb, p.Hin, p.Win, p.Hout, p.Wout), valid


def kw_order(k, stride):
    """kw sequence of one (kh, cb) run.  Stride 2 (phase layout, pad 1): kw = 0 and kw = 2 read the same odd-x
    phase plane at x offsets -1 and 0 (ex >> 1), i.e. base index + 1, so they are visited next to each other."""
    return [0, 2, 1] if (k == 3 and stride == 2) else list(range(k))


def tap_order(k, stride, cin8):
    """Per-tile tap sequence = weight word order within an og: [(kh, kw, cb)], kh outer, cb, kw inner."""
    return [(kh, kw, cb) for kh in range(k) for cb in range(cin8) for kw in kw_order(k, stride)]


def mcol(k, cin8, kh, kw, cb):
    """Column block of the QC matrix M[cout, (kh, kw, cin)] for tap (kh, kw, cb)."""
    return (kh * k + kw) * cin8 + cb


def tap_consec(k, stride, cin8):
    """Per step of tap_order: True if the step is the window shift (base index = previous step's + 1).  Structural
    rule of the AGU: a kw step inside a run (stride 1), or kw 0 -> 2 (stride 2)."""
    return [i > 0 and (stride == 1 or i == 1) for kh in range(k) for cb in range(cin8)
            for i in range(len(kw_order(k, stride)))]


def gather_plan(p):
    """Whole-pass AGU: flat positions [P, Kb] and valid mask [P, Kb], Kb in tap_order (= weight word order)."""
    P = p.Hout * p.Wout
    o = np.arange(P)
    yo, xo = coords(o, p.Wout)
    pos, val = [], []
    for kh, kw, cb in tap_order(p.k, p.stride, p.cin8):
        yi, xi = p.stride * yo + kh - p.pad, p.stride * xo + kw - p.pad
        v = (yi >= 0) & (yi < p.Hin) & (xi >= 0) & (xi < p.Win)
        idx = o + tap_offset(p.in_lay, p.stride, p.pad, kh, kw, cb, p.Hin, p.Win, p.Hout, p.Wout)
        pos.append(np.where(v, flat(np.where(v, idx, 0), p.in_base), 0))
        val.append(v)
    return np.stack(pos, 1), np.stack(val, 1)


def window_plan(p):
    """Model of the AGU kw window over one og (the og loop repeats it): per tile t and step s, the base index
    B = o0 + c, the lane mask, the shift flag and the slot read mask (slot j holds the raw word of index B + j):
      shift  = tap_consec (asserted: B == previous B + 1, and no other step has B == previous B + 1)
      held   = shift ? have >> 1 : 0;   read = lane & ~held;   have = held | lane
    -> dict(base [T, S], lane [T, S, 8], shift [S], read [T, S, 8]); v1 reads = lane (one bank per valid lane)."""
    T = p.Hout * p.Wout // 8
    taps = tap_order(p.k, p.stride, p.cin8)
    shift = np.array(tap_consec(p.k, p.stride, p.cin8))
    base, lane = np.zeros((T, len(taps)), np.int64), np.zeros((T, len(taps), 8), bool)
    for s, (kh, kw, cb) in enumerate(taps):
        for t in range(T):
            idx, v = agu(8 * t, kh, kw, cb, p)
            base[t, s], lane[t, s] = idx[0], v
    seq = base.reshape(-1)                                         # tiles back to back (og repeats the same)
    inc = np.concatenate([[False], seq[1:] == seq[:-1] + 1])
    assert np.array_equal(inc, np.tile(shift, T)), f"{getattr(p, 'name', '?')}: structural shift rule != index rule"
    read = np.zeros_like(lane)
    have = np.zeros(T, np.int64)
    for s in range(len(taps)):
        held = (have >> 1) if shift[s] else np.zeros(T, np.int64)
        m = (lane[:, s] * (1 << np.arange(8))).sum(1)
        r = m & ~held
        read[:, s] = (r[:, None] >> np.arange(8)) & 1
        have = held | m
    return dict(base=base, lane=lane, shift=shift, read=read)


def act_reads(p):
    """Array act-bank reads of a whole pass (all og): (v2 window, v1 one per valid lane)."""
    w = window_plan(p)
    return int(w["read"].sum()) * p.cout64, int(w["lane"].sum()) * p.cout64


def tensor_positions(layout, base, planes, H, W):
    """Flat buffer positions [planes, H, W] of a stored tensor."""
    cb, y, x = np.meshgrid(np.arange(planes), np.arange(H), np.arange(W), indexing="ij")
    return flat(index(layout, cb, y, x, H, W), base)


def words_to_lanes(words):
    """uint64 words [...] -> int8 lanes [..., 8] (lane i = bits 8i+7:8i)."""
    return np.ascontiguousarray(words, dtype=np.uint64).view(np.int8).reshape(words.shape + (8,))


def lanes_to_words(lanes):
    """int lanes [..., 8] (values in int8 range, or uint8 bytes) -> uint64 words [...]."""
    return np.ascontiguousarray(np.asarray(lanes).astype(np.int8)).view(np.uint64)[..., 0]


def read_tensor(buf, layout, base, C, H, W):
    """Flat buffer words [..., 8192] -> int8 map [..., C, H, W] (C = 8 * planes)."""
    pos = tensor_positions(layout, base, C // 8, H, W)
    lanes = words_to_lanes(buf[..., pos])                               # [..., cb, H, W, 8]
    return np.moveaxis(lanes, -1, -3).reshape(buf.shape[:-1] + (C, H, W))


def write_tensor(buf, t, layout, base):
    """int8 map t [..., C, H, W] -> flat buffer words [..., 8192] (in place)."""
    C, H, W = t.shape[-3:]
    pos = tensor_positions(layout, base, C // 8, H, W)
    lanes = np.moveaxis(t.reshape(t.shape[:-3] + (C // 8, 8, H, W)), -3, -1)
    buf[..., pos] = lanes_to_words(lanes)


def split16(R):
    """int16 R [..., C, H, W] -> int8 planes [..., 2C, H, W]: group cb -> planes 2cb (low byte), 2cb+1 (high)."""
    R = np.asarray(R, dtype=np.int64)
    C, H, W = R.shape[-3:]
    lo, hi = (R & 255).astype(np.uint8).view(np.int8), (R >> 8).astype(np.int8)
    g = lambda a: a.reshape(a.shape[:-3] + (C // 8, 1, 8, H, W))
    return np.concatenate([g(lo), g(hi)], -4).reshape(R.shape[:-3] + (2 * C, H, W))


def join16(planes):
    """Inverse of split16: int8 planes [..., 2C, H, W] -> int64 R [..., C, H, W]."""
    C2, H, W = planes.shape[-3:]
    p = np.asarray(planes).reshape(planes.shape[:-3] + (C2 // 16, 2, 8, H, W))
    lo, hi = p[..., 0, :, :, :].astype(np.int64) & 255, p[..., 1, :, :, :].astype(np.int64)
    return (hi * 256 + lo).reshape(planes.shape[:-3] + (C2 // 2, H, W))
