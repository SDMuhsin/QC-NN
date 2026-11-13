"""Binary-map SRAM layout of QC18B-ACC (R2, hw/rtl/qb_act.sv): how the dataflow buffers (compile/dataflow.py, flat
entries pix * C + c, int8 maps one bit-plane after the other) sit in the map macros that feed the line buffer.

Map macros (results/mem.md c): 4 x rf_2p 128 x 128 per map; one *line* = the 4 words of one address = 512 b
(macro m holds line bits 128 m .. 128 m + 127).  Every map row (one input row y of one bit-plane, all channels) is
2048 b for every pass of E6 (W x C = 32 x 64, 16 x 128, 8 x 256, 4 x 512; image: 32 px x 8 planes x 8 ch) = 4 lines:

    row  = plane * H + y                      (binary maps: plane 0; HQ / Z: planes 0..7; IMG: see below)
    pos  = (c >> 5) * (32 W) + x * 32 + (c & 31)   chunk-major inside the row: chunk g = channels 32 g .. 32 g + 31
    line = base + 4 row + (pos >> 9),  macro = (pos >> 7) & 3,  bit = pos & 127

IMG (stem source, 8 planes x 8 channels, 3 real): stored as one 64-channel binary map, channel c' = 8 plane + c, so
the stem's chunk h (= cycle h, groups g = planes 4h + g) is chunk h of that map.  Lines per buffer: B1 / B2 <= 128,
Z 128, HQ 256 (two maps: line bit 7 = map), IMG 128.

    to_lines(t, planes, H, W, C, img=False)   dataflow entries (one image) -> [nlines, 512] uint8 bits
    from_lines(lines, planes, H, W, C, img)   inverse (writers: the PPU's b2 / b1_next / hq / z words go here)
    addr(plane, y, x, c, H, W)                -> (line, macro, bit) of one entry (base 0)
    src_geom(p)                               (planes, H, W, C, img) of an array pass's source map
"""
import numpy as np

LINE, MACRO_W, NMACRO, ROW = 512, 128, 4, 2048


def src_geom(p):
    """source map geometry of an array pass p (compile/program.Pass)."""
    if p.src == "IMG":
        return 1, p.Hin, p.Win, 64, True
    planes = 8 if p.inb == 8 else 1
    assert p.Win * p.cin == ROW, f"{p.name}: row {p.Win} x {p.cin} != {ROW} b"
    return planes, p.Hin, p.Win, p.cin, False


def addr(plane, y, x, c, H, W):
    pos = (c >> 5) * 32 * W + x * 32 + (c & 31)
    line = 4 * (plane * H + y) + (pos >> 9)
    return line, (pos >> 7) & 3, pos & 127


def _img_to_c64(t, H, W):
    """IMG entries plane * L * 8 + pix * 8 + c -> [H, W, 64] with channel 8 plane + c."""
    return np.asarray(t).reshape(8, H, W, 8).transpose(1, 2, 0, 3).reshape(H, W, 64)


def to_lines(t, planes, H, W, C, img=False):
    t = np.asarray(t).reshape(-1)
    if img:
        m = _img_to_c64(t[:8 * H * W * 8], H, W)[None]
        planes, C = 1, 64
    else:
        m = t[:planes * H * W * C].reshape(planes, H, W, C)
    assert W * C == ROW
    rows = m.reshape(planes, H, W, C // 32, 32).transpose(0, 1, 3, 2, 4).reshape(planes * H, ROW)
    return rows.reshape(planes * H * 4, LINE).astype(np.uint8)


def from_lines(lines, planes, H, W, C, img=False):
    Cs = 64 if img else C
    P = 1 if img else planes
    m = np.asarray(lines).reshape(P, H, Cs // 32, W, 32).transpose(0, 1, 3, 2, 4).reshape(P, H, W, Cs)
    if img:
        return m[0].reshape(H, W, 8, 8).transpose(2, 0, 1, 3).reshape(-1)
    return m.reshape(-1)


def _selftest():
    rng = np.random.default_rng(0)
    for planes, H, W, C, img in ((1, 32, 32, 64, False), (1, 16, 16, 128, False), (8, 8, 8, 256, False),
                                 (8, 4, 4, 512, False), (1, 32, 32, 64, True)):
        n = 8 * H * W * 8 if img else planes * H * W * C
        t = rng.integers(0, 2, n)
        ln = to_lines(t, planes, H, W, C, img)
        assert np.array_equal(from_lines(ln, planes, H, W, C, img), t)
        if not img:
            for _ in range(200):
                pl, y, x, c = (int(rng.integers(0, v)) for v in (planes, H, W, C))
                line, m, b = addr(pl, y, x, c, H, W)
                assert ln[line, 128 * m + b] == t[pl * H * W * C + (y * W + x) * C + c]
    return "layout self-test PASS"


if __name__ == "__main__":
    print(_selftest())
