#!/usr/bin/env python3
"""Ideal-clock view of the pre-CTS DC SDF for the sdf run: every IOPATH of the clock-network cells
(clock_cells.txt from write_sdf.tcl: clock gates CKLNQD* and the buffers / muxes / gates between
the clock port and the register clock pins) is zeroed. Synthesis and STA time the netlist with
ideal clocks (CTS balances these delays away later); keeping them would skew the gated clocks
against the ungated ones and fail hold in a way no real layout does. Everything else is kept.
Streams:  zcat dc.sdf.gz | sdf_idealclk.py clock_cells.txt | gzip > idealclk.sdf.gz
"""
import re
import sys

clk = {l.split()[0] for l in open(sys.argv[1]) if l.strip()}
triple = re.compile(r"\(-?[\d.]*:-?[\d.]*:-?[\d.]*\)")
hit, n, cells = False, 0, 0
for line in sys.stdin:
    if line.startswith("  (INSTANCE "):
        hit = line[12:].strip().rstrip(")") in clk
        cells += hit
    elif hit and "(IOPATH " in line:
        line = triple.sub("(0.000:0.000:0.000)", line)
        n += 1
    sys.stdout.write(line)
print(f"sdf_idealclk: {cells}/{len(clk)} clock cells found, {n} IOPATHs zeroed", file=sys.stderr)
