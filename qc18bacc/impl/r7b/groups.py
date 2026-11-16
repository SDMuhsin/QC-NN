#!/usr/bin/env python3
"""impl/r7b (results/r7b.md): group rectangles (<run>/mplace.tcl.groups, read by impl/r6b/grp_place.tcl) for the
column-sliced south logic and the west-strip variants, from a placed floorplan <run>/mplace.tcl (impl/r6b/mplace.py).
    python3 -I groups.py <mplace.tcl> <out.groups>
env (defaults in brackets):
  QB7_S     [slice]  slice: S0..S7 = the S rows under column c (x of column c, y 0 .. array bottom - QB7_SBUF; column 7
                     to the die edge), SX = the S rows west of the array (SW corner around FC / IMG / params 9);
                     one: a single S group (as R6c)
  QB7_S0W   [0]      slice 0 extended west into the SW corner by this (um), SX narrowed
  QB7_SBUF  [120]    template-free buffer band under the array (r6c_h: the S group ends 120 um below the array)
  QB7_WEST  [r6c]    r6c: WA = west strip from the array bottom up QB7_WAH [1980], W = rest of the strip + NW corner;
                     full: WA = the whole west strip from the array bottom to the descriptor macros (sequencer out),
                     W = strip above the descriptors + NW corner + north band (shared with N)
  QB7_PINS  [0]      1: rewrite ::QB_PIN_Y of <mplace.tcl> (chip IO pins on the west edge) to the NW corner (W)
Prints the rectangles and their areas."""
import os
import re
import sys

E = lambda k, d: os.environ.get(k, d)
mp, out = sys.argv[1], sys.argv[2]
txt = open(mp).read()
dieW, dieH = map(float, re.search(r"P\(DIE_AREA\) \{0 0 ([0-9.]+) ([0-9.]+)\}", txt).groups())
pl = re.findall(r"\{(\S+) ([0-9.]+) ([0-9.]+) (\S+)\}", txt)
col = sorted((float(x), float(y)) for n, x, y, o in pl if "__u_col" in n)
x0, ya = col[0]
BW, BH, HG = 390.0, 3110.0, 10.0
yt = ya + BH
xw = min(float(x) for n, x, y, o in pl if "g_wl_" in n)
yn = min(float(y) for n, x, y, o in pl if "g_wl_" in n)
yd = min(float(y) for n, x, y, o in pl if "g_d_u_mac" in n)
stop = round(ya - float(E("QB7_SBUF", 120)), 1)
w0 = float(E("QB7_S0W", 0))
G = {}
if E("QB7_S", "slice") == "slice":
    for c in range(8):
        G["S%d" % c] = [(x0 + c * BW - (w0 if c == 0 else 0.0), 0.0, dieW if c == 7 else x0 + (c + 1) * BW, stop)]
    G["SX"] = [(0.0, 0.0, x0 - w0, stop)]
else:
    G["S"] = [(0.0, 0.0, dieW, stop)]
if E("QB7_WEST", "r6c") == "full":
    G["WA"] = [(0.0, ya, x0, yd - HG)]
    G["W"] = [(0.0, yd - HG, x0, yn), (0.0, yn, xw - HG, dieH), (x0, yt, dieW, yn)]
else:
    yw = ya + float(E("QB7_WAH", 1980))
    G["WA"] = [(0.0, ya, x0, yw)]
    G["W"] = [(0.0, yw, x0, yn), (0.0, yn, xw - HG, dieH)]
G["N"] = [(x0, yt, dieW, yn), (xw - HG, yn, dieW, dieH)]
with open(out, "w") as f:
    for g, rs in G.items():
        f.write(g + " " + " ".join("%.1f %.1f %.1f %.1f" % r for r in rs) + "\n")
        print("GROUP %-3s %s  bbox area %.3f mm2" % (g, " ".join("(%.1f %.1f %.1f %.1f)" % r for r in rs),
                                                   sum((r[2] - r[0]) * (r[3] - r[1]) for r in rs) / 1e6))
if E("QB7_PINS", "0") == "1":
    txt = re.sub(r"set ::QB_PIN_Y \{[^}]*\}", "set ::QB_PIN_Y {%.1f %.1f}" % (yn + 100, dieH - 100), txt)
    open(mp, "w").write(txt)
    print("PINS west edge y %.1f-%.1f" % (yn + 100, dieH - 100))
print("GEOM die %.1f x %.1f = %.4f mm2, array x0 %.1f y %.1f-%.1f, weights x %.1f y %.1f, descriptors y %.1f, S top %.1f"
      % (dieW, dieH, dieW * dieH / 1e6, x0, ya, yt, xw, yn, yd, stop))
