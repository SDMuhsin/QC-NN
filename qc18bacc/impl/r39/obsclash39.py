#!/usr/bin/env python3
"""R39: top wire shapes near a block (impl/r39/wires39.tcl, block-relative um) vs the OBS rects of a block LEF
(impl/r36/lefgeo.sh .geo, "O OBS <layer> x1 y1 x2 y2"): count overlaps and spacing < S (default 0.1 um) per layer, for
the old and the new view.   python3 -I obsclash39.py <wires.txt> <lef.geo> [S]"""
import sys
from collections import defaultdict, Counter
wf, gf = sys.argv[1:3]; S = float(sys.argv[3]) if len(sys.argv) > 3 else 0.1
G = 20.0; obs = defaultdict(list)
for ln in open(gf):
    t = ln.split()
    if t[0] != "O": continue
    l = t[2]; r = tuple(map(float, t[3:7]))
    for gx in range(int(r[0] // G), int(r[2] // G) + 1):
        for gy in range(int(r[1] // G), int(r[3] // G) + 1): obs[(l, gx, gy)].append(r)
ov, sp, nets = Counter(), Counter(), set()
for ln in open(wf):
    t = ln.split(); l = t[0]; x1, y1, x2, y2 = map(float, t[1:5])
    hit = 0
    seen = set()
    for gx in range(int((x1 - S) // G), int((x2 + S) // G) + 1):
        for gy in range(int((y1 - S) // G), int((y2 + S) // G) + 1):
            for r in obs.get((l, gx, gy), ()):
                if r in seen: continue
                seen.add(r)
                dx = max(r[0] - x2, x1 - r[2]); dy = max(r[1] - y2, y1 - r[3])
                if dx < 0 and dy < 0: hit = max(hit, 2)
                elif max(dx, dy) < S and not (dx >= 0 and dy >= 0): hit = max(hit, 1)
    if hit == 2: ov[l] += 1; nets.add(t[5])
    elif hit == 1: sp[l] += 1; nets.add(t[5])
print("R39CLASH %s overlaps %s spacing<%.2f %s nets %d" % (gf, dict(ov), S, dict(sp), len(nets)))
