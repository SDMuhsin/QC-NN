"""Measured (RTL sim log) vs modelled (qc18acc.compile.golden.cycles) cycles per pass.
python3 -m qc18acc.hw.sim.cycles SIM_LOG EXPORT_DIR [image]"""
import re
import sys

import numpy as np

from qc18acc.compile.golden import act_reads, cycles
from qc18acc.compile.program import MODES, read_program


def main():
    log, d = sys.argv[1], sys.argv[2]
    img = int(sys.argv[3]) if len(sys.argv) > 3 else None
    desc = np.array([int(l, 16) for l in open(f"{d}/desc.hex") if l.strip()], dtype=np.uint32)
    model = cycles(dict(desc=desc))
    prog = read_program(desc)
    meas, perf, ard = {}, None, None
    for l in open(log):
        m = re.match(r"PASSCYC img (\d+) pass (\d+) (\S+)\s+(\d+)", l)
        if m and (img is None or int(m[1]) == img):
            img = int(m[1])
            meas[int(m[2])] = (m[3], int(m[4]))
        m = re.match(r"PERF img (\d+) total (\d+) array_busy (\d+) .* stall (\d+) param_load (\d+)", l)
        if m and int(m[1]) == img:
            perf = [int(v) for v in m.groups()[1:]]
            m = re.search(r"act_reads (\d+)", l)
            ard = int(m[1]) if m else None
    print(f"image {img}: measured RTL cycles vs cycle MODEL")
    print(f"{'pass':>4s} {'name':14s} {'mode':6s} {'K':>4s} {'meas':>7s} {'model':>7s} {'diff %':>7s}")
    for i, (mc, d_) in enumerate(zip(model, prog)):
        name, c = meas.get(i, ("?", 0))
        K = d_.k * d_.k * d_.cin8 if d_.type == 1 else 0
        mode = MODES[d_.mode] if d_.type == 1 else "head"
        print(f"{i:4d} {name:14s} {mode:6s} {K:4d} {c:7d} {mc:7d} {100 * (c - mc) / mc:+7.1f}")
    tm, tc = sum(model), sum(c for _, c in meas.values())
    print(f"     {'total':14s} {'':6s} {'':4s} {tc:7d} {tm:7d} {100 * (tc - tm) / tm:+7.1f}")
    if perf:
        tot, busy, stall, pl = perf
        print(f"START..DONE {tot} cycles; array busy {busy} ({100 * busy / tot:.1f} %), AGU stall {stall}, "
              f"param-load {pl}")
    ar = act_reads(dict(desc=desc))
    v2, v1 = sum(a for a, _ in ar), sum(b for _, b in ar)
    if ard is not None:
        print(f"array act-bank reads: measured {ard} ({ard / tot:.3f} / cycle), MODEL v2 window {v2} "
              f"({'equal' if ard == v2 else 'DIFFERS'}), v1 one per valid lane {v1} ({v2 / v1:.3f}x)")


if __name__ == "__main__":
    main()
