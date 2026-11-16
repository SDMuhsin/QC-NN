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


# ------------------------------------------------------------------------------------------------ R10a: physical layouts
# S lane l = 8 r + c sits under column c (row r); a map bit of channel ch is produced by column (ch >> 3) & 7 (fused lane
# 64 q + 8 c + i / wide lane 8 q + c, channel 64 ct + 8 c + i).  phys_old = the default RTL (qb_top.sv header: rotated
# lane-words), phys_col = QB_WB_COL (column-local).  Both keep the logical words above; the hub selects 16 lanes and
# qb_act2 applies T (QB_WB_COL), so the program / flags / addresses s_ra are identical (no compile change).
PITCH = 390.0                                   # column pitch (um, R9b mplace9)
_RD = lambda pl: (pl & 3) + 8 * (pl >> 2)


def _bits(kind, a, pos):
    """logical (address, bit) -> (pl, ct64, column, fields)."""
    o = a - BASE[kind]
    if kind == "hq":
        pl, g = o >> 3, o & 7
        y, x, c5 = pos >> 8, (pos >> 5) & 7, pos & 31
        return pl, g >> 1, 4 * (g & 1) + (c5 >> 3), dict(y=y, x=x, i=c5 & 7, g=g)
    if kind == "hqd":
        pl, h = o >> 1, o & 1
        tq, oy, ox, c5 = pos >> 9, (pos >> 7) & 3, (pos >> 5) & 3, pos & 31
        t = 4 * h + tq
        return pl, t >> 1, 4 * (t & 1) + (c5 >> 3), dict(oy=oy, ox=ox, i=c5 & 7, h=h)
    pl, q4 = o >> 2, o & 3
    gq, y, x, c5 = pos >> 9, (pos >> 7) & 3, (pos >> 5) & 3, pos & 31
    g = 4 * q4 + gq
    return pl, g >> 1, 4 * (g & 1) + (c5 >> 3), dict(y=y, x=x, i=c5 & 7, q4=q4)


def phys_old(kind, a, pos):
    pl, ct, c, f = _bits(kind, a, pos)
    l = pos >> 7
    if kind == "hq":
        return (l + 2 * pl + (f["g"] & 1)) & 15, a, pos & 127
    base = 128 if kind == "hqd" else 144
    return 16 + ((l + _RD(pl)) & 15), base + a - BASE[kind], pos & 127


def phys_col(kind, a, pos):
    """QB_WB_COL: (physical lane, physical address, in-lane bit); lane & 7 == producing column."""
    pl, ct, c, f = _bits(kind, a, pos)
    if kind == "hq":
        y, x, i = f["y"], f["x"], f["i"]
        tp, k, q = y >> 1, 2 * (y & 1) + (x >> 2), x & 3
        r = (tp + pl) & 3
        return 8 * r + c, (128 if r < 2 else 176) + 4 * pl + ct, 32 * k + 8 * q + i
    if kind == "hqd":
        oy, ox, i = f["oy"], f["ox"], f["i"]
        return 16 + 8 * ((oy ^ pl) & 1) + c, 128 + 2 * pl + f["h"], 64 * (ct & 1) + 32 * (oy >> 1) + 8 * ox + i
    y, x, i = f["y"], f["x"], f["i"]
    return 16 + 8 * ((ct ^ pl) & 1) + c, 144 + 4 * pl + f["q4"], 32 * y + 8 * x + i


def producer_col(kind, a, pos):
    return _bits(kind, a, pos)[2]


def T_act(w):
    """qb_act2 QB_WB_COL transpose: slot 4 G + a, bit 32 b + 8 q + i -> lane 4 G + b, bit 32 q + 8 a + i."""
    v = np.asarray(w).reshape(4, 4, 4, 4, 8)            # [G, a, b, q, i]
    return v.transpose(0, 2, 3, 1, 4).reshape(-1)       # [G, b, q, a, i]


def hub_read_col(mem, kind, a):
    """qb_top g_srd_col: the 16 slots (2048 b) of logical word a from the physical S image mem[(lane, addr)]."""
    o = a - BASE[kind]
    out = np.zeros((16, 128), np.uint8)
    for G in range(4):
        for cc in range(4):
            if kind == "hq":
                pl, g = o >> 3, o & 7
                r = (G + pl) & 3
                out[4 * G + cc] = mem[(8 * r + 4 * (g & 1) + cc, (128 if r < 2 else 176) + 4 * pl + (g >> 1))]
            elif kind == "hqd":
                pl = o >> 1
                for oy in range(4):
                    ln = 16 + 8 * ((oy ^ pl) & 1) + 4 * (G & 1) + cc
                    out[4 * G + cc, 32 * oy:32 * oy + 32] = mem[(ln, 128 + o)][64 * (G >> 1) + 32 * (oy >> 1):][:32]
            else:
                pl = o >> 2
                out[4 * G + cc] = mem[(16 + 8 * ((G >> 1) ^ (pl & 1)) + 4 * (G & 1) + cc, 144 + o)]
    return out.reshape(-1)


def wire_model():
    """write-back bits per map: total, cross-column, x-span (straight line producer column -> lane column), old / col."""
    res = {}
    for kind in ("hq", "hqd", "z"):
        n = {"hq": 64, "hqd": 16, "z": 32}[kind]
        tot = {"old": [0, 0, 0.0], "col": [0, 0, 0.0]}
        for w in range(n):
            a = BASE[kind] + w
            for pos in range(WORD):
                c = producer_col(kind, a, pos)
                for k, f in (("old", phys_old), ("col", phys_col)):
                    d = f(kind, a, pos)[0] & 7
                    tot[k][0] += 1
                    tot[k][1] += d != c
                    tot[k][2] += abs(d - c) * PITCH
        res[kind] = tot
    return res


def net_model():
    """static nets: each core output bit (f_y lane bit pl / w_y lane bit pl) -> the S lane columns it ever writes;
    HPWL in x = (max - min of producer + lane columns) x PITCH; returns {kind: {old/col: (nets, cross nets, m)}}."""
    res = {}
    for kind in ("hq", "hqd", "z"):
        n = {"hq": 64, "hqd": 16, "z": 32}[kind]
        dst = {"old": {}, "col": {}}
        for w in range(n):
            a = BASE[kind] + w
            for pos in range(WORD):
                pl, ct, c, f = _bits(kind, a, pos)
                q = f["x"] & 3 if kind != "hqd" else 2 * (f["ox"] & 1)
                src = (pl, q, c, f["i"]) if kind != "z" else (pl, q, c)      # f_y lane 64 q + 8 c + i / w_y lane 8 q + c
                for k, fn in (("old", phys_old), ("col", phys_col)):
                    dst[k].setdefault(src, {c}).add(fn(kind, a, pos)[0] & 7)
        res[kind] = {k: (len(v), sum(len(s) > 1 for s in v.values()),
                         sum((max(s) - min(s)) * PITCH for s in v.values()) / 1e6) for k, v in dst.items()}
    return res


def _selftest_col():
    rng = np.random.default_rng(2)
    for kind in ("hq", "hqd", "z"):
        n = {"hq": 64, "hqd": 16, "z": 32}[kind]
        seen, mem = set(), {}
        words = {BASE[kind] + w: rng.integers(0, 2, WORD, dtype=np.uint8) for w in range(n)}
        for a, wv in words.items():
            for pos in range(WORD):
                ln, pa, b = phys_col(kind, a, pos)
                assert ln & 7 == producer_col(kind, a, pos), (kind, a, pos)          # column-local
                assert (ln, pa, b) not in seen, (kind, a, pos)                       # no two bits on one cell
                seen.add((ln, pa, b))
                mem.setdefault((ln, pa), np.zeros(128, np.uint8))[b] = wv[pos]
        for a, wv in words.items():                                                 # hub select + T == logical
            assert np.array_equal(T_act(hub_read_col(mem, kind, a)), wv), (kind, a)
    cells = {}
    for kind in ("hq", "hqd", "z"):
        n = {"hq": 64, "hqd": 16, "z": 32}[kind]
        for w in range(n):
            for pos in range(0, WORD, 1):
                ln, pa, _ = phys_col(kind, BASE[kind] + w, pos)
                cells.setdefault((ln, pa), set()).add(kind)
    assert all(len(v) == 1 for v in cells.values())
    assert all(64 <= pa < 128 or 128 <= pa < 208 for (ln, pa) in cells) and \
        not any(ln < 16 and (64 <= pa < 128 or pa >= 192) for (ln, pa) in cells)
    return "layout_s phys_col self-test PASS (column-local, collision-free, hub + T == logical, disjoint from r / stream)"


if __name__ == "__main__":
    import sys
    print(_selftest())
    print(_selftest_col())
    if "--wire" in sys.argv:
        cyc = {"hq": 64, "hqd": 32, "z": 256}         # write cycles per image: hm 64, HQD on the 32 even-row hm cycles, c1 wide 8 ct x 32
        for kind, t in wire_model().items():
            for k in ("old", "col"):
                b, x, sp = t[k]
                print(f"WIRE {kind:3s} {k:3s} bits {b:6d} cross-column {x:6d} ({100 * x / b:5.1f} %) x-span {sp / 1e6:7.3f} m"
                      f" | per write cycle: {x / cyc[kind]:7.1f} b, {sp / cyc[kind] / 1e3:7.2f} mm")
        for kind, t in net_model().items():
            for k in ("old", "col"):
                nn, nx, m = t[k]
                print(f"NETS {kind:3s} {k:3s} source bits {nn:5d} crossing a column {nx:5d} x-HPWL {m:6.3f} m")
