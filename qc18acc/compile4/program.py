"""v4 (16 pixel rows) program = the v3 program unchanged (ARCH.md "v4": QC codes and weight image word for word,
pass schedule, buffers A/B/C, layouts, params, descriptors, bounds and proofs).  v4 adds only layout checks:
every tensor fits 16 banks x 256 x 128 b, every conv output map has >= 16 pixels (one tile), and the drain's pixel
pairs (rows a, a + 2) never share a bank in the output or residual layout of any pass.
"""
from qc18acc.compile.program import RAW16, RES_ID, RES_R  # noqa: F401
from qc18acc.compile3.program import Program3, from_v2

from .layout import BANKS, DEPTH, ROWS, drain_conflicts


def check4(prog3):
    for t in prog3.tensors.values():
        npairs = (t.planes + 1) // 2
        assert npairs * t.H * t.W % BANKS == 0 and t.base + npairs * t.H * t.W // BANKS <= DEPTH, f"{t.name} does not fit"
    for p in prog3.passes:
        assert p.Hout * p.Wout >= ROWS and (p.Hout * p.Wout) % ROWS == 0, f"{p.name}: output map < one 16-pixel tile"
        npo = (8 if p.mode == RAW16 else 4) * p.cout64          # output pair planes (int16 R: lo + hi byte planes)
        assert drain_conflicts(p.out_lay, p.Hout, p.Wout, npo) == 0, f"{p.name}: drain write pair in one bank"
        if p.mode in (RES_ID, RES_R):
            npr = (8 if p.mode == RES_R else 4) * p.cout64
            assert drain_conflicts(p.res_lay, p.Hout, p.Wout, npr) == 0, f"{p.name}: drain residual pair in one bank"
    return prog3


def from_v3(prog3):
    return check4(prog3)


def build(net, model):
    from qc18acc.compile.program import build as build2
    return from_v3(from_v2(build2(net, model)))


__all__ = ["Program3", "build", "from_v3", "check4"]
