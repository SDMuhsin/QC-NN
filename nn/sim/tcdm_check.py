#!/usr/bin/env python3
"""Compare a tensor in the final TCDM dump of an RTL run with the integer reference.

    python3 -m nn.sim.tcdm_check <run dir> <tensor> [<more tensors>]
Use with a run built with -DNN_STOP_AFTER=<step> (core 0 freezes after that step, run_nn.tcl dumps
the 32 TCDM banks to out/tcdm_<k>.hex).  TCDM: 32 banks x 64 bit, word-interleaved.
Prints per channel group / row the number of wrong bytes (X counts as wrong) and a few samples.
"""
import re
import sys
from pathlib import Path

import numpy as np
import torch

from ..compile.lower import Program
from ..compile.main import ref_run
from ..model.data import test_set
from ..quant.quantize import BUILD, IntResNet8

NB, WORDS = 32, 512


def read_tcdm(d):
    mem = np.zeros(NB * WORDS * 8, np.int16)          # -1 marks X
    for k in range(NB):
        for line in (Path(d) / f"out/tcdm_{k}.hex").read_text().splitlines():
            line = line.strip()
            if not line.startswith("@"):
                continue
            r, v = line[1:].split()
            a = (int(r, 16) * NB + k) * 8
            for j in range(8):
                byte = v[len(v) - 2 * (j + 1):len(v) - 2 * j]
                mem[a + j] = int(byte, 16) if re.fullmatch(r"[0-9a-fA-F]{2}", byte) else -1
    return mem


def main():
    d = Path(sys.argv[1])
    first = int(re.search(r"--first (\d+)", (d / "cmd.txt").read_text()).group(1)) if (d / "cmd.txt").exists() else 0
    q = torch.load(Path(BUILD) / "qparams.pt", weights_only=False)
    prog = Program(q)
    xt, _ = test_set()
    taps, _ = ref_run(IntResNet8(q), prog, xt[[first]])
    mem = read_tcdm(d)
    blobs = {b.name: b for b in prog.blobs}
    for name in sys.argv[2:]:
        if name in blobs:                                  # constant blob (weights + bias tiles)
            b = blobs[name]
            got = mem[b.addr:b.addr + b.size]
            exp = np.frombuffer(b.data, np.uint8).astype(np.int16)
            bad = np.nonzero(got != exp)[0]
            print(f"{name}: @0x{b.addr:05x} +{b.size}: {len(bad)} bytes wrong"
                  + (f", first at +{bad[0]} (64 B line {bad[0] // 64}), last +{bad[-1]}" if len(bad) else ""))
            continue
        t = prog.tensors[name]
        got = mem[t.addr:t.addr + t.C8 * t.plane].reshape(t.C8, t.Hp, t.Wq, 8)[:, 1:-1, t.X0:t.X0 + t.H, :]
        exp = taps[0][name].astype(np.int16) & 0xFF
        bad = got != exp
        nx = int((got < 0).sum())
        print(f"{name}: @0x{t.addr:05x} C8 {t.C8} H {t.H} pitch {t.Wq}: {int(bad.sum())} of {bad.size} interior bytes wrong ({nx} X)")
        if bad.any():
            for g in range(t.C8):
                rows = [h for h in range(t.H) if bad[g, h].any()]
                if rows:
                    cols = sorted({w for h in rows for w in np.nonzero(bad[g, h].any(-1))[0]})
                    print(f"  group {g}: rows {rows[:6]}{'...' if len(rows) > 6 else ''} ({len(rows)}), cols {cols[:12]}{'...' if len(cols) > 12 else ''}")
            g, h, w = [int(v[0]) for v in np.nonzero(bad.any(-1))]
            print(f"  sample g{g} h{h} w{w}: got {got[g, h, w].tolist()} exp {exp[g, h, w].tolist()}")


if __name__ == "__main__":
    main()
