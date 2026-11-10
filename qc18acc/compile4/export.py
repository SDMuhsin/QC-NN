"""v4 $readmemh images (as v3; output buffers: line = bank * 256 + address, 16 banks) (one word per line, hex, MSB first; 'x' digits = word not written by that pass).

<dir>/weights_e.hex / weights_o.hex  80-b even / odd weight SRAM halves (20 digits)
<dir>/params.hex  72-b param SRAM (18)   <dir>/desc.hex  32-b descriptor RAM (8)   <dir>/program.txt  passes, sizes
<dir>/img<n>/input.hex             input pair plane, 1024 x 128-b words (32 digits) in raster index order
<dir>/img<n>/logits.hex / .txt     10 int32 FC accumulators + bias
<dir>/img<n>/pass<ii>_<name>.hex   output buffer after pass ii: 4096 x 128 b, line = bank * 256 + address
"""
import os

import numpy as np

from qc18acc.compile.export import _hexw, _wide
from qc18acc.compile.program import BUFS, MODES

from .layout import BANKS, DEPTH, tensor_positions


def w128(w):
    return [int(lo) | (int(hi) << 64) for lo, hi in w]


def export(d, prog, act0, logits, snaps, ids):
    os.makedirs(d, exist_ok=True)
    im = prog.images
    _hexw(os.path.join(d, "weights_e.hex"), _wide(im["weights_e"]), 20)
    _hexw(os.path.join(d, "weights_o.hex"), _wide(im["weights_o"]), 20)
    _hexw(os.path.join(d, "params.hex"), _wide(im["params"]), 18)
    _hexw(os.path.join(d, "desc.hex"), im["desc"], 8)
    with open(os.path.join(d, "program.txt"), "w") as f:
        for k, v in prog.sizes().items():
            f.write(f"{k} {v}\n")
        for i, p in enumerate(prog.passes):
            f.write(f"pass {i:02d} {p.name} k{p.k} s{p.stride} {p.Hin}x{p.Win}->{p.Hout}x{p.Wout} cin8 {p.cin8} "
                    f"cout64 {p.cout64} {MODES[p.mode]} in {BUFS[p.in_buf]}+{p.in_base} out {BUFS[p.out_buf]}+"
                    f"{p.out_base} res {BUFS[p.res_buf] if p.res else '-'} wbase {p.wbase} pbase {p.pbase}\n")
        h = prog.head
        f.write(f"head in {BUFS[h.in_buf]}+{h.in_base} fc wbase {h.wbase} (even half) bias pbase {h.pbase}\n")
    for n, i in enumerate(ids):
        g = os.path.join(d, f"img{i}")
        os.makedirs(g, exist_ok=True)
        t = prog.tensors["img"]
        pos = tensor_positions(t.lay, t.base, 1, t.H, t.W).ravel()
        _hexw(os.path.join(g, "input.hex"), w128(act0[n, t.buf][pos]), 32)
        _hexw(os.path.join(g, "logits.hex"), [int(v) & 0xFFFFFFFF for v in logits[n]], 8)
        with open(os.path.join(g, "logits.txt"), "w") as f:
            f.writelines(f"{int(v)}\n" for v in logits[n])
        for j, p in enumerate(prog.passes):
            t = prog.tensors[p.dst]
            mask = np.zeros(BANKS * DEPTH, bool)
            mask[tensor_positions(t.lay, t.base, (t.planes + 1) // 2, t.H, t.W).ravel()] = True
            with open(os.path.join(g, f"pass{j:02d}_{p.name}.hex"), "w") as f:
                f.writelines(f"{w:032x}\n" if m else "x" * 32 + "\n" for w, m in zip(w128(snaps[j][n]), mask))
