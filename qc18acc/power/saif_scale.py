#!/usr/bin/env python3
"""Rescale a SAIF to another clock period with the same toggles per cycle (qc18acc/power/power.sh).

    saif_scale.py <factor> <in.saif> > <out.saif>

Multiplies DURATION and every state time (T0, T1, TX, TZ) by <factor> (= new period / simulated period) and keeps
the toggle counts (TC, IG): PrimeTime then sees the same transitions per cycle and the same state probabilities at
the new clock, i.e. the power of the same work at another frequency (dynamic energy per cycle unchanged, leakage x
period).
"""
import re
import sys

f = float(sys.argv[1])
pat = re.compile(r"\((DURATION|T0|T1|TX|TZ) ([0-9.]+)\)")


def sub(m):
    v = float(m.group(2)) * f
    return f"({m.group(1)} {v:.2f})" if m.group(1) == "DURATION" else f"({m.group(1)} {round(v)})"


with open(sys.argv[2]) as src:
    for line in src:
        sys.stdout.write(pat.sub(sub, line) if "(T" in line or "(DURATION" in line else line)
