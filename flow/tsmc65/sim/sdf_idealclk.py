#!/usr/bin/env python3
"""GLS view of a pre-CTS DC SDF, consistent with the STA that signed the netlist off.

1. Ideal clocks: every IOPATH of the clock-network cells is zeroed. The cells are given as
   --clock-cells FILE (instance names, first column, e.g. clock_cells.txt from a write_sdf run:
   clock gates and the buffers / muxes / gates between the clock port and the register clock
   pins) and / or --clock-celltype PREFIX (every cell whose SDF CELLTYPE starts with PREFIX,
   e.g. CKLNQD for the integrated clock gates when they are the whole clock network).
   Synthesis and STA time the netlist with ideal clocks (CTS balances these delays away later);
   keeping them would skew the gated clocks against the ungated ones and fail hold in a way no
   real layout does.
2. Ideal reset: the reset port is an ideal network and a false path in the SDC, so STA never saw
   the delays of the buffer / inverter tree DC hung on it (up to ~1.3 ns of wire-load estimate on
   a 60k-sink net). They are zeroed too: the tree is found from the SDF's own INTERCONNECTs,
   starting at <rst_port> and following single-input cells (input pin I: BUFF*/CKB*/INV*/CKND*).
   Otherwise the deassertion lands on a clock edge for some flops and not for others.
3. Input delay: every INTERCONNECT that starts at a top-level input port other than the clock
   (inputs driven by the RTL testbench in the same delta as the clock edge) gets <input_delay_ns>,
   the SDC set_input_delay that STA assumes for min and max. Without it a TB input changes 0 ps
   after the edge, the shortest port-to-register paths are ~10 ps, the cells' SDF hold (and
   negative setup) windows extend past the edge, and the simulator's delayed-signal model of those
   windows captures the value of the NEXT cycle: no timing-check message, just a one-cycle-early
   handshake (impl/snitch_cluster/gls/README.md, "SDF run").
Everything else (cell, interconnect, timing-check values) is kept.

  sdf_idealclk.py [--clock-cells FILE] [--clock-celltype PREFIX ...] <dc.sdf[.gz]>
                  [input_delay_ns [clock_port [rst_port]]] | gzip > idealclk.sdf.gz
Options go before the positional arguments (Python 3.6 argparse on the hosts).
"""
import argparse
import collections
import gzip
import re
import sys

ap = argparse.ArgumentParser(description="STA-consistent (ideal clock / reset, input delay) view of a DC SDF")
ap.add_argument("--clock-cells", help="file with the clock-network instance names (first column)")
ap.add_argument("--clock-celltype", action="append", default=[], help="CELLTYPE prefix of clock-network cells")
ap.add_argument("sdf")
ap.add_argument("input_delay_ns", nargs="?", type=float, default=0.0)
ap.add_argument("clock_port", nargs="?", default="clk_i")
ap.add_argument("rst_port", nargs="?", default="rst_ni")
a = ap.parse_args()
if not a.clock_cells and not a.clock_celltype:
    ap.error("give --clock-cells and / or --clock-celltype")
src_path, dly, clkport, rstport = a.sdf, a.input_delay_ns, a.clock_port, a.rst_port
opn = (lambda p: gzip.open(p, "rt")) if src_path.endswith(".gz") else open
ctypes = tuple('  (CELLTYPE "' + p for p in a.clock_celltype)

ideal = set()
if a.clock_cells:
    with open(a.clock_cells) as f:
        ideal = {l.split()[0] for l in f if l.strip()}
nclk = len(ideal)

# pass 1: reset tree from the INTERCONNECTs (source instance -> destination pins)
fan = collections.defaultdict(list)
with opn(src_path) as f:
    for line in f:
        if line.startswith("    (INTERCONNECT "):
            s, d = line.split()[1:3]
            fan[s.rsplit("/", 1)[0] if "/" in s else s].append(d)
        elif line.startswith("(CELL") and fan:
            break
rst, sinks, todo = set(), 0, [rstport]
while todo:
    for d in fan.get(todo.pop(), ()):
        inst, pin = d.rsplit("/", 1)
        if pin == "I" and inst not in rst:
            rst.add(inst)
            todo.append(inst)
        else:
            sinks += 1
del fan
ideal |= rst

# pass 2: rewrite
triple = re.compile(r"\(-?[\d.]*:-?[\d.]*:-?[\d.]*\)")
d3 = f"({dly:.3f}:{dly:.3f}:{dly:.3f})"
ctype = hit = False
n = cells = nct = nin = 0
out = sys.stdout
with opn(src_path) as f:
    for line in f:
        if line.startswith("  (CELLTYPE "):
            ctype = bool(ctypes) and line.startswith(ctypes)
        elif line.startswith("  (INSTANCE "):
            hit = ctype or line[12:].strip().rstrip(")") in ideal
            cells += hit
            nct += ctype
        elif hit and "(IOPATH " in line:
            line = triple.sub("(0.000:0.000:0.000)", line)
            n += 1
        elif dly and line.startswith("    (INTERCONNECT "):
            src = line.split()[1]
            if "/" not in src and src.split("[")[0] != clkport:
                line = triple.sub(d3, line)
                nin += 1
        out.write(line)
print(f"sdf_idealclk: {nclk} listed clock cells, {nct} cells of type {'/'.join(a.clock_celltype) or '-'}, "
      f"{len(rst)} reset-tree cells ({sinks} reset sink pins); {cells} cells found, {n} IOPATHs zeroed; "
      f"{nin} input-port INTERCONNECTs set to {dly:.3f} ns", file=sys.stderr)
