#!/usr/bin/env python3
"""R14: which DRV-repair nets (impl/r14/probe_drv.tcl drv_nets.txt) must cross a hard block?  A net crosses block B
if its pin bbox spans B completely in y (or x) while overlapping it in the other axis (no route around inside the
bbox); a pin-to-pin block-only net has no top std-cell terminal at all.  R11 geometry by default (fp11: hub 0..3990 x
0..1601.6, array 860..3980 x 1601.6..4711.6, act 80..860 x 2291.6..4711.6); repair max wire length QB14_MWL [757 um].
    python3 -I drv_geo.py <drv_nets.txt> [geometry: name:x1,y1,x2,y2 ...]"""
import os
import sys
from collections import Counter

f = sys.argv[1]
G = {"hub": (0, 0, 3990, 1601.6), "array": (860, 1601.6, 3980, 4711.6), "act": (80, 2291.6, 860, 4711.6)}
for a in sys.argv[2:]:
    n, v = a.split(":"); G[n] = tuple(map(float, v.split(",")))
mwl = float(os.environ.get("QB14_MWL", 757))
C = Counter(); L = Counter()
for ln in open(f):
    p = ln.split()
    if p[0] != "net":
        continue
    nt, nb, ms, h = int(p[4]), int(p[5]), p[6], float(p[7])
    x1, y1, x2, y2 = map(float, p[8:12])
    ms_s = set(ms.split(","))
    blkonly = "std" not in ms_s and "io" not in ms_s
    cr = []
    for b, (bx1, by1, bx2, by2) in G.items():
        ov_x = x1 < bx2 and x2 > bx1; ov_y = y1 < by2 and y2 > by1
        if (ov_x and y1 <= by1 and y2 >= by2) or (ov_y and x1 <= bx1 and x2 >= bx2):
            cr.append(b)
    k = ("block-only" if blkonly else "top") + (" crosses " + "+".join(sorted(cr)) if cr else " no crossing") + (" >MWL" if h > mwl else " <=MWL")
    C[k] += 1; L[k] += h
print("# DRV-violating nets by block crossing (%s), max wire length %.0f um: class nets sum_hpwl_mm [repair buffers ~ hpwl/MWL]" % (f, mwl))
for k, v in sorted(C.items(), key=lambda z: -L[z[0]]):
    print("%-44s %7d %9.1f %8.0f" % (k, v, L[k] / 1000, L[k] / mwl if ">MWL" in k else 0))
