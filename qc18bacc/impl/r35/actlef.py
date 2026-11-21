#!/usr/bin/env python3
"""R35: act-block view for the top P&R before the act abstract exists: pins of an early write_abstract_lef (floorplan db)
+ full-area OBS M1-M7 (impl/r11/lefio.write_macro), so the top routes over the block on M8 / M9 only.
usage: actlef.py <early.lef> <out.lef> [W H]"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "r11"))
from lefio import read_macro, write_macro
src, dst = sys.argv[1:3]
name, W, H, pins = read_macro(src)
if len(sys.argv) > 4: W, H = float(sys.argv[3]), float(sys.argv[4])
pins = {p: v for p, v in pins.items() if p not in ("VDD", "VSS")}
write_macro(dst, name, W, H, pins, ["M1", "M2", "M3", "M4", "M5", "M6", "M7"])
print("ACTLEF %s %.1f x %.1f pins %d" % (name, W, H, len(pins)))
