"""Random mini program for fast RTL regressions (iverilog): the qc18acc compiler's own pass schedule / buffer /
layout planner on a small ResNet (H = 8; stem 64, identity block, conv-shortcut stride-2 block, head), random
legal QC codes / params / FC weights, golden-model expected images, exported in the same format as
`qc18acc.compile.main --export`.
    python3 -m qc18acc.hw.tb.mini DIR [--images 2] [--seed 0]"""
import argparse

import numpy as np

from qc18acc.compile import codes as K
from qc18acc.compile.export import export
from qc18acc.compile.golden import Golden
from qc18acc.compile.layout import BANKS, DEPTH, write_tensor
from qc18acc.compile.program import RAW16, RES_ID, Program, encode_desc, plan, weight_words


def build(rng, blocks, H):
    P, head, T = plan(blocks, H=H, stem_cout=64)
    vb = K.valid_blocks()
    ww, pw = [], []
    for p in P:
        cds = K.encode(vb[rng.integers(0, len(vb), (64 * p.cout64, p.K))])
        p.wbase = len(ww)
        ww += weight_words(p, cds)
        p.pbase = len(pw)
        n = 64 * p.cout64
        bias = rng.integers(-3000, 3000, n)
        m0 = rng.integers(2 ** 29, 2 ** 31, n)
        sh = rng.integers(34, 37, n) if p.name != "stem" else rng.integers(32, 34, n)
        pw += [K.param_word(int(b), int(m), int(s), int(d)) for b, m, s, d in zip(bias, m0, sh, rng.integers(0, 2, n))]
        if p.mode == RES_ID:
            p.idm0, p.idsh = int(rng.integers(2 ** 29, 2 ** 31)), 31
    head.ncls = 10
    head.wbase = len(ww)
    W8 = rng.integers(-127, 128, (10, 8 * head.cin8))
    for cb in range(head.cin8):
        for j in range(10):
            ww.append(K.fc_word(W8[j, 8 * cb:8 * cb + 8]))
    head.pbase = len(pw)
    pw += [K.param_word(int(b), 0, 0, 0) for b in rng.integers(-100000, 100000, 10)]
    head.pool_m0, head.pool_sh = int(rng.integers(2 ** 29, 2 ** 31)), 35
    desc = [w for p in P for w in encode_desc(p)] + encode_desc(head)
    return Program(P, head, T, K.to_wide(ww), K.to_wide(pw), np.array(desc, dtype=np.uint32))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--images", type=int, default=2)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--H", type=int, default=8)
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed)
    prog = build(rng, [(64, 64, 1), (64, 128, 2), (128, 128, 1)], a.H)
    t = prog.tensors["img"]
    x = np.zeros((a.images, 8, t.H, t.W), np.int64)
    x[:, :3] = rng.integers(-127, 128, (a.images, 3, t.H, t.W))
    act = np.zeros((a.images, 3, BANKS * DEPTH), np.uint64)
    write_tensor(act[:, t.buf], x, t.lay, t.base)
    act0 = act.copy()
    logits, snaps, _ = Golden(prog.images).run(act)
    export(a.dir, prog, act0, logits, snaps, list(range(a.images)))
    print(f"mini program: {len(prog.passes)} passes + head, {len(prog.images['weights'])} weight words -> {a.dir}")


if __name__ == "__main__":
    main()
