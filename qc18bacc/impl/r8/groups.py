#!/usr/bin/env python3
"""impl/r8 (results/r8.md): group rectangles for the R8 floorplan (impl/r6b/mplace.py placement, R6c G/H recipe) with
the per-column head pool slices of the r7h_rp netlist (QB_HEAD_PCOL: u_head/g_pcol_<c>__u_pc) in their own regions.
    python3 -I groups.py <mplace.tcl> <out.groups>
Groups (read by impl/r6b/grp_place.tcl, imported by impl/r7b/place.tcl over QB7_GROUPS):
  P0..P7  pool slice c: x of column c (390 um), y from (array bottom - QB8_SBUF - QB8_PH) to (array bottom - QB8_SBUF),
          i.e. directly under column c's south pins, below the template-free buffer band (r6c_h: 120 um)
  S       the R6c S group (y 0 .. array bottom - QB8_SBUF) minus the P strip
  WA / W  R6c (QB8_WAH [1980] above the array bottom); QB8_WA_HARD 1 drops WA (hook for the R7c WA hard block:
          the strip is then left to the block's macro placement, see impl/r8/chip.cfg QB8_WA_TCL)
  N       R6c
env: QB8_SBUF [120], QB8_PH [80] (um); QB8_NOP 1: control without P groups (S as R6c); QB8_SWAP 1: see below."""
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
stop = round(ya - float(E("QB8_SBUF", 120)), 1)
pb = round(stop - float(E("QB8_PH", 80)), 1)
xr = x0 + 8 * BW
G = {}
SWAP = E("QB8_SWAP", "0") == "1"
# QB8_SWAP 1 (impl/r8/mplace.py QB8_SWAP): WA = SW corner (x < array, y < array bottom) + west strip up to the bottom of
# the moved FC macro (QB8_WAY, default = FC bottom); W = the rest of the west strip (around FC / IMG / params 9) + NW
if SWAP:
    fy = min(float(y) for n, x, y, o in pl if "g_f_u_mac" in n or "qb_f" in n or "/g_mac_g_f" in n)
    way = float(E("QB8_WAY", fy - HG))
    G["WA"] = [(0.0, 0.0, x0, way)]
if E("QB8_NOP", "0") == "1":    # control: no pool-slice regions (slices stay in S, as R6c's head)
    G["S"] = [((x0 if SWAP else 0.0), 0.0, dieW, stop)]
else:
    G["S"] = ([(x0, 0.0, dieW, pb)] if SWAP else [(0.0, 0.0, dieW, pb), (0.0, pb, x0, stop)]) + ([(xr, pb, dieW, stop)] if dieW - xr >= 5 else [])
    for c in range(8):
        G["P%d" % c] = [(x0 + c * BW, pb, x0 + (c + 1) * BW, stop)]
yw = ya + float(E("QB8_WAH", 1980))
if SWAP:
    G["W"] = [(0.0, way, x0, yn), (0.0, yn, xw - HG, dieH)]
else:
    if E("QB8_WA_HARD", "0") != "1":
        G["WA"] = [(0.0, ya, x0, yw)]
    G["W"] = [(0.0, yw, x0, yn), (0.0, yn, xw - HG, dieH)]
G["N"] = [(x0, yt, dieW, yn), (xw - HG, yn, dieW, dieH)]
with open(out, "w") as f:
    for g, rs in G.items():
        f.write(g + " " + " ".join("%.1f %.1f %.1f %.1f" % r for r in rs) + "\n")
        print("GROUP %-3s %s  bbox area %.3f mm2" % (g, " ".join("(%.1f %.1f %.1f %.1f)" % r for r in rs),
                                                   sum((r[2] - r[0]) * (r[3] - r[1]) for r in rs) / 1e6))
print("GEOM die %.1f x %.1f = %.4f mm2, array x0 %.1f y %.1f-%.1f, S top %.1f, P strip y %.1f-%.1f"
      % (dieW, dieH, dieW * dieH / 1e6, x0, ya, yt, stop, pb, stop))
