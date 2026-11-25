#!/usr/bin/env python3
"""Hub qb_hub SDC + IO budget from the boundary table (impl/r9b/bnd.py <out>_bits.txt; results/r9b.md, r31.md).
    python3 -I blocks/hub/sdc.py <bnd_bits.txt> <period ns> <out.sdc> <out_io.tcl>
(The comment lines written into both files name the original impl/r9b/sdc.py: the generated files are byte-identical.)
Budget, fractions of P, relative to the clock at the hub flops (ideal clock; after CTS the flow shifts inputs + L,
outputs - L, L = QB_IO_LAT, as impl/r5a/budget.tcl):
  from columns (f_y, b2, w_y, f_b, w_b, *_vld_o)  input 0.27 P = column output budget 0.25 P (impl/r5a/budget.tcl) + pin
  to column south pins (pf, pw, s_rd, w_r, ctl's) output 0.20 P = column south-input budget 0.20 P (abutted)
  to column north pins (t2, ctl, rst_n)           output 0.55 P = column north budget 0.30 P + ~3.1 mm over the array
  to act supply (s_q, m_q, ...)                   output 0.30 P = act block input budget 0.70 P (impl/r7c/budget.tcl)
  from act supply                                 input 0.40 P
  top (sequencer, glue, chip IO)                  input 0.40 P, output 0.40 P
  host write registers                            input 0.30 P
  min: inputs 0.05 P, outputs 0
act hold budget (R81, PI decision): the hub's act output to column 0 (the head of the point-to-point act chain) has
output -min = -QC_ACT_HOLD_HUB, the one value common/env.sh exports (os.environ["QC_ACT_HOLD_HUB"], ns).  The column
budget charges the same value once on its act input -min (blocks/col/io_budget.tcl qb5_act_in_min: qb5_hold_min +
QC_ACT_HOLD_HUB): every column sees the hub's minimum arrival plus upstream feedthroughs, so the hub alone guarantees it."""
import sys
from collections import defaultdict

bits, per, osdc, oio = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]
NORTH = ("t2", "ctl", "rst_n", "cd", "clk")
B = {"colin": ("in", 0.27), "colout": ("out", 0.20), "colnorth": ("out", 0.55), "actout": ("out", 0.30),
     "actin": ("in", 0.40), "topin": ("in", 0.40), "topout": ("out", 0.40), "hostin": ("in", 0.30)}
cl = defaultdict(list)
for ln in open(bits):
    f = ln.split()
    p, d, c, bus = f[0], f[1], f[3], f[4]
    if c in ("clk",):
        continue
    if bus.startswith("col."):
        pins = bus[4:].split("/")
        k = "colin" if d == "in" else ("colnorth" if any(x in NORTH for x in pins) else "colout")
    elif c == "rst":
        k = "topin"
    elif c.startswith("act") and "+" not in c:
        k = "actout" if d == "out" else "actin"
    elif c == "host" and d == "in":
        k = "hostin"
    else:
        k = "topin" if d == "in" else "topout"
    cl[k].append(p)
with open(osdc, "w") as f:
    f.write("# R9b hub SDC (impl/r9b/sdc.py), period %.3f ns\n" % per)
    f.write("create_clock -name qb_clk -period %.4f -waveform {0 %.4f} [get_ports clk]\n" % (per, per / 2))
    f.write("set_clock_uncertainty -setup 0.25 [get_clocks qb_clk]\nset_clock_uncertainty -hold 0.05 [get_clocks qb_clk]\n")
    f.write("set_clock_transition 0.15 [get_clocks qb_clk]\n")
    f.write("set_max_transition %.4f [current_design]\nset_max_fanout 16 [current_design]\n" % min(0.5, 0.1 * per))
    f.write("set_driving_cell -lib_cell BUFFD4 -pin Z [all_inputs]\nset_load 0.010 [all_outputs]\n")
    # ARM macro EMA* = 000 / RETN = 1 (hw/tech/qb_mem_tech.sv): without case analysis OpenSTA takes the worst `when` arc,
    # the uncharacterised EMA = 100 clk -> Q table of 999 ns (r9b_f place STA -999 ns)
    # R31 (results/r31.md): OpenSTA's */EMA* also matches 1816 macro QA outputs (R29 / R30), so OR never timed the
    # memory-read paths; the regexp matches the 282 EMA / EMAA / EMAB bits only, in OpenSTA and PT alike
    f.write("set_case_analysis 0 [get_pins -hierarchical -regexp {.*/EMA[AB]?\\[[0-9]+\\]}]\nset_case_analysis 1 [get_pins -hierarchical */RETN]\n")
    f.write("set_false_path -to [get_pins -hierarchical */CLKA]\nset_false_path -to [get_pins -hierarchical */CLKB]\n")
    f.write("source %s\nqb9_io_apply %.4f 0.0\n" % (__import__("os").path.abspath(oio), per))
with open(oio, "w") as f:
    f.write("# R9b hub IO budget (impl/r9b/sdc.py); qb9_io_apply per L; qb5_io_apply = hook of impl/pnr/slice_post_cts.tcl\n")
    for k, ps in sorted(cl.items()):
        f.write("set ::QB9_IO(%s) {%s}\n" % (k, " ".join("{%s}" % p for p in ps)))
    f.write("proc qb9_io_apply {per {L 0.0}} {\n")
    for k, (d, fr) in sorted(B.items()):
        if not cl.get(k):
            continue
        cmd = "set_input_delay" if d == "in" else "set_output_delay"
        sh = "$L" if d == "in" else "-$L"
        mn = "0.05" if d == "in" else "0.0"
        f.write("    %s -max [expr {%.3f * $per + %s}] -clock qb_clk [get_ports $::QB9_IO(%s)]\n" % (cmd, fr, sh, k))
        f.write("    %s -min [expr {%s * $per + %s}] -clock qb_clk [get_ports $::QB9_IO(%s)]\n" % (cmd, mn, sh, k))
    f.write("}\nproc qb5_io_apply {per {L 0.0}} { qb9_io_apply $per $L }\n")
print("SDC classes " + " ".join("%s %d" % (k, len(v)) for k, v in sorted(cl.items())))
