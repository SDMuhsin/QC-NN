"""v3 (Kb = 2) program: the v2 compiler (qc18acc.compile.program: pass schedule, buffers, layouts, params,
descriptors, per-layer proofs) re-packed for two blocks per PE per cycle (ARCH.md "v3").

Weights: per array step (kh, pair j, kw) two 80-b words at the SAME address of two memories: even half = codes of the
input group 2j (v2 word of tap (kh, kw, 2j)), odd half = group 2j + 1 (zero word if 2j + 1 = cin8, i.e. the stem).
Order per pass: og outer, then layout.tap_order (kh, j, kw).  The FC words follow the conv words in the even half.
Params and descriptors: v2 formats unchanged (cin8 stays the group count; the hardware derives ceil(cin8 / 2)).
Extra v3 proofs: |d acc + bias| < 2^19 (the PPU holds v in 20 b) and |bias| < 2^19 (the drain RF keeps 20 b),
on top of v2's |acc| < 2^19, |R| < 2^15; capacity: every tensor fits 8 banks x 512 x 128 b.
"""
import copy

import numpy as np

from qc18acc.compile import codes as K
from qc18acc.compile.layout import tap_order as tap_order2
from qc18acc.compile.program import Head, RAW16, RES_ID, RES_R, encode_desc, read_program  # noqa: F401

from .layout import BANKS, DEPTH, cinp, tap_order

V_BITS = 20                                            # PPU v register (signed)


class Program3:
    def __init__(self, passes, head, tensors, we, wo, params, desc, v2):
        self.passes, self.head, self.tensors, self.v2 = passes, head, tensors, v2
        self.images = dict(weights_e=we, weights_o=wo, params=params, desc=desc)

    def sizes(self):
        im = self.images
        ne, no = len(im["weights_e"]), len(im["weights_o"])
        return dict(weight_words_even=ne, weight_words_odd=no, weight_bytes=(ne + no) * K.WEIGHT_BITS // 8,
                    param_words=len(im["params"]), desc_words=len(im["desc"]), act_bytes=3 * BANKS * DEPTH * 16)


def pass_codes(w2, d):
    """v2 weight words of a pass -> codes [cout64, (kh, kw, cb) -> 8 column codes] dict per og."""
    taps = tap_order2(d.k, d.stride, d.cin8)
    n = d.cout64 * len(taps)
    cds = K.word_codes(w2[d.wbase:d.wbase + n]).reshape(d.cout64, len(taps), 8)
    return [{t: cds[og, i] for i, t in enumerate(taps)} for og in range(d.cout64)]


def words3(w2, d):
    """-> (even words, odd words) of one pass, as ints, in v3 array order."""
    ev, od = [], []
    zero = np.zeros(8, np.int64)
    for c in pass_codes(w2, d):
        for kh, kw, j in tap_order(d.k, d.stride, d.cin8):
            ev.append(K.weight_word(c[(kh, kw, 2 * j)]))
            od.append(K.weight_word(c.get((kh, kw, 2 * j + 1), zero)))
    return ev, od


def prove3(p):
    """v3 bounds from the v2 per-pass proof (worst case over all inputs in range)."""
    pr = p.proof
    pr["v3_v"] = pr["v"] < 2 ** (V_BITS - 1)
    assert pr["v3_v"], f"{p.name}: |d acc + bias| bound {pr['v']} >= 2^19: network refused (v3 PPU v is 20 b)"
    return pr


def check_capacity(T):
    for t in T.values():
        npairs = (t.planes + 1) // 2
        assert npairs * t.H * t.W % BANKS == 0 and t.base + npairs * t.H * t.W // BANKS <= DEPTH, f"{t.name} does not fit"


def from_v2(prog2, proofs=True):
    """v2 Program (qc18acc.compile.program.build or hw/tb/mini.build) -> Program3."""
    im = prog2.images
    w2, params = im["weights"], im["params"]
    passes = [copy.copy(p) for p in prog2.passes]
    head = copy.copy(prog2.head)
    check_capacity(prog2.tensors)
    ev, od = [], []
    bias = K.param_fields(params)[0]
    for p in passes:
        assert p.cin8 == 1 or p.cin8 % 2 == 0, f"{p.name}: odd cin8 {p.cin8}"
        e, o = words3(w2, p)
        p.wbase = len(ev)
        ev += e
        od += o
        assert np.abs(bias[p.pbase:p.pbase + 64 * p.cout64]).max() < 2 ** (V_BITS - 1), f"{p.name}: |bias| >= 2^19"
        if proofs:
            prove3(p)
    fc = w2[prog2.head.wbase:prog2.head.wbase + head.cin8 * head.ncls]
    head.wbase = len(ev)
    we = np.concatenate([K.to_wide(ev), fc])
    desc = [w for p in passes for w in encode_desc(p)] + encode_desc(head)
    return Program3(passes, head, prog2.tensors, we, K.to_wide(od), params, np.array(desc, dtype=np.uint32), prog2)


def build(net, model):
    from qc18acc.compile.program import build as build2
    return from_v2(build2(net, model))
