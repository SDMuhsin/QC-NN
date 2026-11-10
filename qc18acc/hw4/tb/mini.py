"""v4 random mini program for fast RTL regressions (iverilog): the v2 mini program (hw/tb/mini.py: H = 8, stem 64,
identity block, conv-shortcut stride-2 block, head; random legal codes / params / FC) re-packed for Kb = 2 (v3 = v4 program)
(compile3.program.from_v2 + compile4 checks), v4 golden expected images, exported like `qc18acc.compile4.main --export`.
    python3 -m qc18acc.hw4.tb.mini DIR [--images 2] [--seed 0]"""
import argparse

import numpy as np

from qc18acc.compile4.export import export
from qc18acc.compile4.golden import Golden4
from qc18acc.compile4.layout import BANKS, DEPTH, write_tensor
from qc18acc.compile4.program import check4
from qc18acc.compile3.program import from_v2
from qc18acc.hw.tb.mini import build


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--images", type=int, default=2)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--H", type=int, default=8)
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed)
    prog = check4(from_v2(build(rng, [(64, 64, 1), (64, 128, 2), (128, 128, 1)], a.H), proofs=False))
    t = prog.tensors["img"]
    x = np.zeros((a.images, 8, t.H, t.W), np.int64)
    x[:, :3] = rng.integers(-127, 128, (a.images, 3, t.H, t.W))
    act = np.zeros((a.images, 3, BANKS * DEPTH, 2), np.uint64)
    write_tensor(act[:, t.buf], x, t.lay, t.base)
    act0 = act.copy()
    logits, snaps, _ = Golden4(prog.images).run(act)
    export(a.dir, prog, act0, logits, snaps, list(range(a.images)))
    print(f"v4 mini program: {len(prog.passes)} passes + head, {len(prog.images['weights_e'])} + "
          f"{len(prog.images['weights_o'])} weight words -> {a.dir}")


if __name__ == "__main__":
    main()
