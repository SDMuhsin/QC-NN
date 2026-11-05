#!/usr/bin/env python3
"""GLS view of the pre-CTS DC SDF for the sdf run, consistent with the STA that signed it off
(same method as impl/snitch_cluster/gls/sdf_idealclk.py):

1. Ideal clocks: the CP->Q delays of the integrated clock-gating cells (CKLNQD*, the whole clock
   network of this netlist) are zeroed. STA times the netlist with ideal clocks (CTS balances the
   ICG insertion delay away later); keeping the ~0.15 ns would skew every gated flop against the
   ungated ones.
2. Ideal reset: the reset port is an ideal network and a false path in the SDC, so STA never saw
   the delays of the buffer / inverter tree on it. They are zeroed too: the tree is found from the
   SDF's own INTERCONNECTs, from <rst_port> through single-input cells (input pin I).
3. Input delay: every INTERCONNECT from a top-level input port other than the clock gets
   <input_delay_ns>, the SDC set_input_delay (min = max). chimera drives the cluster inputs from
   RTL flops in the same delta as the clock edge; with 0 ps the shortest port-to-register paths
   (~10 ps) sit inside the cells' hold / negative-setup windows, and the simulator's delayed-signal
   model of those windows samples the next cycle's value: no timing-check message, just
   handshakes one cycle early (results/gls.txt).
Everything else (cell, interconnect, timing-check values, the ICG E/TE setup/hold) is kept.
  sdf_idealclk.py <in.sdf[.gz]> [input_delay_ns [clock_port [rst_port]]] | gzip > out.sdf.gz
"""
import collections
import gzip
import re
import sys

src_path = sys.argv[1]
dly = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
clkport = sys.argv[3] if len(sys.argv) > 3 else "clk_i"
rstport = sys.argv[4] if len(sys.argv) > 4 else "rst_ni"
opn = (lambda p: gzip.open(p, "rt")) if src_path.endswith(".gz") else open

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

# pass 2: rewrite
triple = re.compile(r"\(-?[\d.]*:-?[\d.]*:-?[\d.]*\)")
d3 = f"({dly:.3f}:{dly:.3f}:{dly:.3f})"
icg = hit = False
nicg = nrst = nin = 0
out = sys.stdout
with opn(src_path) as f:
    for line in f:
        if line.startswith("  (CELLTYPE "):
            icg = line.startswith('  (CELLTYPE "CKLNQD')
        elif line.startswith("  (INSTANCE "):
            hit = line[12:].strip().rstrip(")") in rst
        elif (icg or hit) and "(IOPATH " in line:
            line = triple.sub("(0.000:0.000:0.000)", line)
            nicg += icg
            nrst += hit
        elif dly and line.startswith("    (INTERCONNECT "):
            src = line.split()[1]
            if "/" not in src and src.split("[")[0] != clkport:
                line = triple.sub(d3, line)
                nin += 1
        out.write(line)
print(f"sdf_idealclk: zeroed {nicg} ICG and {nrst} reset-tree IOPATH lines ({len(rst)} reset-tree "
      f"cells, {sinks} reset sink pins); {nin} input-port INTERCONNECTs set to {dly:.3f} ns",
      file=sys.stderr)
