#!/usr/bin/env python3
"""Steady-state SAIF window from two Verilator SAIFs of the same deterministic run (R4 power, results/r4.md).

    saif_window.py <A.saif> <B.saif> <sim_period_units> <period_ns> > window.saif

A runs from time 0 to the go of image k, B from time 0 to the go of image k-1 (tb_qb_chip QBT_SAIF +saif_stop), so
A - B (TC, T0, T1, TZ, TX, TB, DURATION) is exactly the interval [go k-1, go k).  Verilator's SAIF ignores
$dumpoff, hence the subtraction.  The times are rescaled so that one simulated clock period (sim_period_units, in the
file's TIMESCALE units) lasts period_ns: toggles per cycle are kept, PrimeTime PX then reads rates at that clock.
Both files must list the same nets in the same order (same binary, same plusargs except +saif_stop)."""
import re
import sys

a_f, b_f, simp, pns = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
num = re.compile(r"\((T0|T1|TZ|TX|TB|TC) (\d+)\)")
ts_unit = {"fs": 1e-6, "ps": 1e-3, "ns": 1.0}
scale = None
with open(a_f) as fa, open(b_f) as fb:
    for la, lb in zip(fa, fb):
        if la.startswith("(TIMESCALE"):
            m = re.match(r"\(TIMESCALE (\d+)(fs|ps|ns)\)", la)
            unit_ns = int(m.group(1)) * ts_unit[m.group(2)]
            scale = pns / (simp * unit_ns) * unit_ns * 1000.0 / 1.0   # new value in ps per old unit
            scale = pns * 1000.0 / simp                                # ps per old unit (one period -> pns)
            sys.stdout.write("(TIMESCALE 1ps)\n")
            continue
        if la.startswith("(DURATION"):
            da = int(la.split()[1].rstrip(")")); db = int(lb.split()[1].rstrip(")"))
            sys.stdout.write(f"(DURATION {round((da - db) * scale)})\n")
            continue
        if "(TC " not in la:
            sys.stdout.write(la)
            continue
        vb = dict((k, int(v)) for k, v in num.findall(lb))
        def sub(m):
            k, v = m.group(1), int(m.group(2))
            d = v - vb.get(k, 0)
            if d < 0:
                d = 0
            return f"({k} {d if k == 'TC' else round(d * scale)})"
        sys.stdout.write(num.sub(sub, la))
