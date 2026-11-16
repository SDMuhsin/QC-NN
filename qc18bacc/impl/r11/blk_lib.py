#!/usr/bin/env python3
"""R11: budget liberty (proxy ETM) for a block without an extracted model (hub: no routed hub yet; act: R9a not
routed).  Pins / directions from the block LEF.  Arcs relative to the block clk pin, ideal block clock (no insertion):
  input  setup = (1 - f) P   (f = the block's input budget: share of P left to the outside, as the block SDC)
  output clk -> pin = (1 - f) P
  hub (f per impl/r9b/sdc.py classes of bnd_bits.txt): colin .27, colout .20, colnorth .55, actout .30, actin .40,
       topin / topout .40, hostin .30
  act (impl/r7c/budget.tcl roles): s_q / m_q inputs: registered at the pin (sdq / rdq) -> setup 0.25 P; other inputs
       0.50 P; act outputs straight from the pipe flops: 0.25 P; other outputs 0.50 P
Hold: 0.05 ns hold constraint on inputs, min clk -> pin = 0.15 ns.  tt values; ss = tt x 1.6, ff = tt x 0.8.
    python3 -I blk_lib.py <period ns> <block.lef> <bnd_bits.txt | -> <hub|act> <out prefix>   -> <out>_{tt,ss,ff}.lib"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lefio import read_macro

per, lef, bits, kind, out = float(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
name, W, H, pins = read_macro(lef)
frac = {}
if kind == "hub":
    NORTH = ("t2", "ctl", "rst_n", "cd", "clk")
    F = {"colin": .27, "colout": .20, "colnorth": .55, "actout": .30, "actin": .40, "topin": .40, "topout": .40, "hostin": .30}
    for ln in open(bits):
        f = ln.split()
        p, d, c, bus = f[0], f[1], f[3], f[4]
        if bus.startswith("col."):
            k = "colin" if d == "in" else ("colnorth" if any(x in NORTH for x in bus[4:].split("/")) else "colout")
        elif c == "rst":
            k = "topin"
        elif c.startswith("act") and "+" not in c:
            k = "actout" if d == "out" else "actin"
        elif c == "host" and d == "in":
            k = "hostin"
        else:
            k = "topin" if d == "in" else "topout"
        frac[p] = F[k]


def f_of(p, d):
    if kind == "hub":
        return frac.get(p, 0.40)
    b = p.split("[")[0]
    if d == "INPUT":
        return 0.75 if b in ("s_q", "m_q") else 0.50
    return 0.75 if b == "act" else 0.50


import re
widths = set()
for p in pins:
    m = re.match(r"^(.*)\[(\d+)\]$", p)
    if m:
        widths.add(m.group(1))
rng = {}         # bus -> (hi, lo): the block's port range (DC writes partial ranges, e.g. [5183:1943])
for p in pins:
    m = re.match(r"^(.*)\[(\d+)\]$", p)
    if m:
        k = int(m.group(2)); h, l = rng.get(m.group(1), (k, k)); rng[m.group(1)] = (max(h, k), min(l, k))
btypes = "".join('  type (%s_b%d_%d) { base_type : array ; data_type : bit ; bit_width : %d ; bit_from : %d ; bit_to : %d ; downto : true ; }\n'
                 % (name, h, l, h - l + 1, h, l) for h, l in sorted(set(rng.values())))
for corner, s in (("tt", 1.0), ("ss", 1.6), ("ff", 0.8)):
    with open("%s_%s.lib" % (out, corner), "w") as f:
        f.write('library (%s_%s) {\n  delay_model : table_lookup ;\n  time_unit : "1ns" ;\n  voltage_unit : "1V" ;\n'
                '  current_unit : "1mA" ;\n  pulling_resistance_unit : "1kohm" ;\n  capacitive_load_unit (1, pf) ;\n'
                '  nom_process : 1 ;\n  nom_voltage : %s ;\n  nom_temperature : 25 ;\n'
                '  operating_conditions (%s) { process : 1 ; voltage : %s ; temperature : 25 ; }\n'
                '  default_operating_conditions : %s ;\n'
                '  input_threshold_pct_rise : 50 ;\n  input_threshold_pct_fall : 50 ;\n  output_threshold_pct_rise : 50 ;\n'
                '  output_threshold_pct_fall : 50 ;\n  slew_lower_threshold_pct_rise : 10 ;\n  slew_upper_threshold_pct_rise : 90 ;\n'
                '  slew_lower_threshold_pct_fall : 10 ;\n  slew_upper_threshold_pct_fall : 90 ;\n'
                '%s'
                '  cell (%s) {\n    area : %.1f ;\n    interface_timing : true ;\n    dont_use : true ;\n    dont_touch : true ;\n'
                % (name, corner, {"tt": "1.0", "ss": "0.9", "ff": "1.1"}[corner], corner,
                   {"tt": "1.0", "ss": "0.9", "ff": "1.1"}[corner], corner, btypes, name, W * H))
        f.write('    pin (clk) { direction : input ; clock : true ; capacitance : 0.05 ; }\n')
        grp = {}
        for p, (d, *_r) in pins.items():
            if p == "clk":
                continue
            m = re.match(r"^(.*)\[(\d+)\]$", p)
            grp.setdefault(m.group(1) if m else p, []).append((int(m.group(2)) if m else None, p, d))
        def body(p, d):
            v = (1.0 - f_of(p, d)) * per * s
            if d == "INPUT":
                return ('      pin ("%s") { direction : input ; capacitance : 0.004 ;\n'
                        '        timing () { related_pin : "clk" ; timing_type : setup_rising ;\n'
                        '          rise_constraint (scalar) { values ("%.4f") ; } fall_constraint (scalar) { values ("%.4f") ; } }\n'
                        '        timing () { related_pin : "clk" ; timing_type : hold_rising ;\n'
                        '          rise_constraint (scalar) { values ("0.05") ; } fall_constraint (scalar) { values ("0.05") ; } } }\n'
                        % (p, v, v))
            return ('      pin ("%s") { direction : output ; max_capacitance : 0.3 ;\n'
                    '        timing () { related_pin : "clk" ; timing_type : rising_edge ;\n'
                    '          cell_rise (scalar) { values ("%.4f") ; } cell_fall (scalar) { values ("%.4f") ; }\n'
                    '          rise_transition (scalar) { values ("0.10") ; } fall_transition (scalar) { values ("0.10") ; } } }\n'
                    % (p, v, v))
        for g, l in sorted(grp.items()):
            if l[0][0] is None:
                f.write(body(g, l[0][2]))
                continue
            h, lo = rng[g]
            assert len(l) == h - lo + 1, ("non-contiguous bus", g, len(l), h, lo)
            d = l[0][2]
            f.write('    bus ("%s") { bus_type : %s_b%d_%d ; direction : %s ;\n' % (g, name, h, lo, "input" if d == "INPUT" else "output"))
            for k, p, dd in sorted(l):
                f.write(body(p, dd))
            f.write('    }\n')
        f.write('  }\n}\n')
print("BLK_LIB %s %s: %d pins, period %.3f" % (kind, name, len(pins), per))
