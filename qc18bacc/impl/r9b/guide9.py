#!/usr/bin/env python3
"""R9b: GRT guide demand per layer and x-region vs nominal track capacity (no macro obstruction subtracted).
    python3 -I guide9.py <route.guide> <tech.lef> [x0 860] [die_w 3990] [die_h 1700.6]
Demand = guide length along the layer's preferred direction (um); capacity = tracks (pitch from the LEF) x span."""
import re
import sys
from collections import defaultdict

g, lef = sys.argv[1], sys.argv[2]
x0 = float(sys.argv[3]) if len(sys.argv) > 3 else 860.0
W = float(sys.argv[4]) if len(sys.argv) > 4 else 3990.0
H = float(sys.argv[5]) if len(sys.argv) > 5 else 1700.6
t = open(lef).read()
L = {}
for m in re.finditer(r"LAYER (M\d)\s+TYPE ROUTING ;(.*?)END \1", t, re.S):
    d = re.search(r"DIRECTION (\w+)", m.group(2)).group(1)
    p = float(re.search(r"PITCH ([\d.]+)", m.group(2)).group(1))
    L[m.group(1)] = (d[0], p)
reg = lambda x: "west" if x < x0 else "col%d" % min(7, int((x - x0) // 390))
D = defaultdict(float)
u = 2000.0
for ln in open(g):
    f = ln.split()
    if len(f) == 5 and f[4] in L:
        x1, y1, x2, y2 = (float(v) / u for v in f[:4])
        d, p = L[f[4]]
        ln_ = (x2 - x1) if d == "H" else (y2 - y1)
        if d == "H":       # split H guides over regions
            a = x1
            while a < x2 - 1e-6:
                r = reg(a); b = min(x2, x0 if r == "west" else x0 + 390 * (int((a - x0) // 390) + 1))
                if r == "col7": b = x2
                D[(f[4], r)] += b - a; a = b
        else:
            D[(f[4], reg((x1 + x2) / 2))] += ln_
regs = ["west"] + ["col%d" % c for c in range(8)]
print("# demand / nominal capacity in % per layer and region (guides; M1 / macro OBS not subtracted)")
print("layer dir pitch " + " ".join("%6s" % r for r in regs) + "  total")
for ly in sorted(L, key=lambda s: int(s[1:])):
    d, p = L[ly]
    row = []
    tot_d = tot_c = 0.0
    for r in regs:
        w = x0 if r == "west" else (390.0 if r != "col7" else W - x0 - 7 * 390)
        cap = (H / p) * w if d == "H" else (w / p) * H
        row.append(100.0 * D[(ly, r)] / cap); tot_d += D[(ly, r)]; tot_c += cap
    print("%-5s %s %.2f " % (ly, d, p) + " ".join("%6.1f" % v for v in row) + "  %5.1f" % (100.0 * tot_d / tot_c))
