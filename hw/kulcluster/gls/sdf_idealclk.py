#!/usr/bin/env python3
"""Ideal-clock view of a pre-CTS DC SDF: zero the CP->Q delays of the integrated clock-gating
cells (CKLNQD*). Synthesis / STA time the netlist with ideal clocks (the ICG insertion delay is
balanced away by clock-tree synthesis later); keeping the ~0.15 ns ICG delay in simulation would
skew every gated flop against the ungated ones and fail hold checks that no real (CTS) layout
has. Everything else (cell, interconnect, timing-check values, the ICG E/TE setup/hold) is kept.
Streams (the SDF is ~1 GB):  sdf_idealclk.py in.sdf | gzip > out.sdf.gz
"""
import re
import sys

triple = re.compile(r"\(-?[\d.]+:-?[\d.]+:-?[\d.]+\)")
icg = False
n = 0
with open(sys.argv[1]) as f:
    out = sys.stdout
    for line in f:
        if line.startswith("  (CELLTYPE "):
            icg = line.startswith('  (CELLTYPE "CKLNQD')
        elif icg and "(IOPATH " in line:
            line = triple.sub("(0.000:0.000:0.000)", line)
            n += 1
        out.write(line)
print(f"sdf_idealclk: zeroed {n} ICG CP->Q arcs (IOPATH lines)", file=sys.stderr)
