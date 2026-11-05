#!/usr/bin/env python3
"""GLS view of the pre-CTS DC SDF for the sdf run, consistent with the STA that signed it off.

1. Ideal clocks: every IOPATH of the clock-network cells (clock_cells.txt from write_sdf.tcl: clock
   gates CKLNQD* and the buffers / muxes / gates between the clock port and the register clock
   pins) is zeroed. Synthesis and STA time the netlist with ideal clocks (CTS balances these
   delays away later); keeping them would skew the gated clocks against the ungated ones and fail
   hold in a way no real layout does.
2. Ideal reset: the reset port is an ideal network and a false path in the SDC, so STA never saw
   the delays of the buffer / inverter tree DC hung on it (up to ~1.3 ns of wire-load estimate on
   a 60k-sink net). They are zeroed too: the tree is found from the SDF's own INTERCONNECTs,
   starting at <rst_port> and following single-input cells (input pin I: BUFF*/CKB*/INV*/CKND*).
   Otherwise the deassertion lands on a clock edge for some flops and not for others.
3. Input delay: every INTERCONNECT that starts at a top-level input port other than the clock
   (cluster AXI / interrupt / reset inputs, driven by the RTL testbench in the same delta as the
   clock edge) gets <input_delay_ns>, the SDC set_input_delay that STA assumes for min and max.
   Without it a TB input changes 0 ps after the edge, the shortest port-to-register paths are
   ~10 ps, the cells' SDF hold (and negative setup) windows extend past the edge, and the
   simulator's delayed-signal model of those windows captures the value of the NEXT cycle: no
   timing-check message, just a one-cycle-early handshake (README, "SDF run").
Everything else is kept.
  sdf_idealclk.py <dc.sdf[.gz]> <clock_cells.txt> [input_delay_ns [clock_port [rst_port]]] | gzip > idealclk.sdf.gz
"""
import collections
import gzip
import re
import sys

src_path, ck_path = sys.argv[1], sys.argv[2]
dly = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
clkport = sys.argv[4] if len(sys.argv) > 4 else "clk_i"
rstport = sys.argv[5] if len(sys.argv) > 5 else "rst_ni"
opn = (lambda p: gzip.open(p, "rt")) if src_path.endswith(".gz") else open

ideal = {l.split()[0] for l in open(ck_path) if l.strip()}
nclk = len(ideal)

# pass 1: reset tree from the INTERCONNECTs (source pin -> destination pins)
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
hit, n, cells, nin = False, 0, 0, 0
out = sys.stdout
with opn(src_path) as f:
    for line in f:
        if line.startswith("  (INSTANCE "):
            hit = line[12:].strip().rstrip(")") in ideal
            cells += hit
        elif hit and "(IOPATH " in line:
            line = triple.sub("(0.000:0.000:0.000)", line)
            n += 1
        elif dly and line.startswith("    (INTERCONNECT "):
            src = line.split()[1]
            if "/" not in src and src.split("[")[0] != clkport:
                line = triple.sub(d3, line)
                nin += 1
        out.write(line)
print(f"sdf_idealclk: {nclk} clock cells + {len(rst)} reset-tree cells ({sinks} reset sink pins), "
      f"{cells} found, {n} IOPATHs zeroed; {nin} input-port INTERCONNECTs set to {dly:.3f} ns",
      file=sys.stderr)
