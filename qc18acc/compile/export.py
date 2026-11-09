"""$readmemh images (one word per line, hex, MSB first; 'x' digits = word not written by that pass).

<dir>/weights.hex  80-b weight SRAM (20 hex digits)       <dir>/params.hex  72-b param SRAM (18 digits)
<dir>/desc.hex     32-b descriptor RAM (8 digits)          <dir>/program.txt pass list, bases, sizes
<dir>/img<n>/act_<A|B|C>_b<k>.hex  initial act buffer bank k (1024 x 64 b, 16 digits), input plane in C
<dir>/img<n>/input.hex             input plane, 1024 words in raster index order (= C, base 0)
<dir>/img<n>/logits.hex / .txt     10 int32 FC accumulators + bias (two's complement hex / decimal)
<dir>/img<n>/pass<ii>_<name>.hex   output buffer after pass ii: 8192 lines, line = bank * 1024 + address
"""
import os

import numpy as np

from .layout import BANKS, DEPTH, tensor_positions
from .program import BUFS, MODES


def _hexw(path, words, digits):
    with open(path, "w") as f:
        f.writelines(f"{int(w):0{digits}x}\n" for w in words)


def _wide(w):
    return [int(lo) | (int(hi) << 64) for lo, hi in w]


def export(d, prog, act0, logits, snaps, ids):
    os.makedirs(d, exist_ok=True)
    im = prog.images
    _hexw(os.path.join(d, "weights.hex"), _wide(im["weights"]), 20)
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
        f.write(f"head in {BUFS[h.in_buf]}+{h.in_base} fc wbase {h.wbase} bias pbase {h.pbase}\n")
    for n, i in enumerate(ids):
        g = os.path.join(d, f"img{i}")
        os.makedirs(g, exist_ok=True)
        for b in range(3):
            for k in range(BANKS):
                _hexw(os.path.join(g, f"act_{BUFS[b]}_b{k}.hex"), act0[n, b, k * DEPTH:(k + 1) * DEPTH], 16)
        t = prog.tensors["img"]
        _hexw(os.path.join(g, "input.hex"), act0[n, t.buf][tensor_positions(t.lay, t.base, 1, t.H, t.W).ravel()], 16)
        _hexw(os.path.join(g, "logits.hex"), [int(v) & 0xFFFFFFFF for v in logits[n]], 8)
        with open(os.path.join(g, "logits.txt"), "w") as f:
            f.writelines(f"{int(v)}\n" for v in logits[n])
        for j, p in enumerate(prog.passes):
            t = prog.tensors[p.dst]
            mask = np.zeros(BANKS * DEPTH, bool)
            mask[tensor_positions(t.lay, t.base, t.planes, t.H, t.W).ravel()] = True
            with open(os.path.join(g, f"pass{j:02d}_{p.name}.hex"), "w") as f:
                f.writelines(f"{int(w):016x}\n" if m else "x" * 16 + "\n" for w, m in zip(snaps[j][n], mask))
