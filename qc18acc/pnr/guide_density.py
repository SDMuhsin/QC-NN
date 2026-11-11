#!/usr/bin/env python3
"""Per-tile global-route guide demand relative to track capacity (relative indicator, as results/pnr_v3.md 11.2).
guide_density.py <guide file> <dbu/um> <tile um> <x0 y0 x1 y1 window um> [hot x0 y0 x1 y1]
For each guide rectangle on M2-M7, its long dimension is added to the tile of its centre (layer pitch 0.2 um,
tracks per tile = tile / 0.2); ratio = guide length / (tile * tracks).  Prints the distribution over the window and the
mean over an optional hot window."""
import sys, collections
f, dbu, t = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
wx0, wy0, wx1, wy1 = map(float, sys.argv[4:8])
hot = list(map(float, sys.argv[8:12])) if len(sys.argv) > 8 else None
L = collections.defaultdict(float)
for line in open(f):
    w = line.split()
    if len(w) != 5 or w[4] not in ("M2", "M3", "M4", "M5", "M6", "M7"): continue
    x0, y0, x1, y1 = (int(v) / dbu for v in w[:4])
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if not (wx0 <= cx < wx1 and wy0 <= cy < wy1): continue
    L[w[4], int(cx // t), int(cy // t)] += max(x1 - x0, y1 - y0)
cap = t * (t / 0.2)
for lay in ("M2", "M3", "M4", "M5"):
    r = sorted(v / cap for (l, _, _), v in L.items() if l == lay)
    if not r: continue
    n = len(r)
    print(f"{lay}: tiles {n} median {r[n//2]:.2f} p90 {r[9*n//10]:.2f} p99 {r[99*n//100]:.2f} max {r[-1]:.2f} >1.0 {sum(x > 1.0 for x in r)} >1.3 {sum(x > 1.3 for x in r)}")
    if hot:
        h = [v / cap for (l, i, j), v in L.items() if l == lay and hot[0] <= i * t < hot[2] and hot[1] <= j * t < hot[3]]
        if h: print(f"   hot window mean {sum(h)/len(h):.2f} max {max(h):.2f} ({len(h)} tiles)")
top = sorted(((v / cap, l, i * t, j * t) for (l, i, j), v in L.items() if l in ("M2", "M3")), reverse=True)[:12]
for r, l, x, y in top: print(f"  top {l} x {x:.0f} y {y:.0f} ratio {r:.2f}")
