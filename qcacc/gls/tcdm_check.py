"""Byte compare of an s2 step output in the final TCDM dump of a gate-level run (NN_GLS_CHECK of nn/gls/run_gls.sh).

    python3 -m qcacc.gls.tcdm_check <run dir> <step>          env QCACC_MODE qc|gemmx, QC_S2 (s2 int8 qparams)

nn.sim.tcdm_check with the s2 program (qcacc.compile.lower.QCProgram; gemmx mode = 42 per-group calls).  A
per-group step (conv1_g1) checks the groups of its conv written so far (0..1).  Output line format as nn's
("<step>: ... N of M interior bytes wrong (X X)"), which nn/gls/summary.py parses.
"""
import os
import re
import sys
from pathlib import Path

import numpy as np
import torch

from nn.model.data import test_set
from nn.quant.quantize import IntResNet8
from nn.sim.tcdm_check import read_tcdm

from ..compile.lower import QCProgram
from ..compile.main import S2, taps_for


def main():
    d, step = Path(sys.argv[1]), sys.argv[2]
    mode = os.environ.get("QCACC_MODE", "qc")
    first = int(re.search(r"--first (\d+)", (d / "cmd.txt").read_text()).group(1))
    q = torch.load(os.environ.get("QC_S2", S2), weights_only=False)
    prog = QCProgram(q, mode, True if mode == "gemmx" else None)
    xt, _ = test_set()
    taps, _ = taps_for(prog, IntResNet8(q), xt[[first]])
    mem = read_tcdm(d)
    name, g1 = (step.split("_g")[0], int(step.split("_g")[1]) + 1) if "_g" in step else (step, None)
    t = prog.tensors[name]
    got = mem[t.addr:t.addr + t.C8 * t.plane].reshape(t.C8, t.Hp, t.Wq, 8)[:, 1:-1, t.X0:t.X0 + t.H, :]
    exp = taps[0][name].astype(np.int16) & 0xFF
    if g1 is not None:
        got, exp = got[:g1], exp[:g1]
    bad = got != exp
    print(f"{step}: tensor {name} groups {g1 or t.C8} @0x{t.addr:05x}: {int(bad.sum())} of {bad.size} interior bytes wrong "
          f"({int((got < 0).sum())} X)")


if __name__ == "__main__":
    main()
