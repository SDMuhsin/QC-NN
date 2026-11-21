#!/usr/bin/env python3
"""R39: OpenROAD DR marker report (detailed_route -output_drc / -drc_report_iter_step files) -> counts by type, layer,
100-um bin (top 15) and the top source nets / instance prefixes.
    python3 -I drcbin.py <drc.rpt> [bin um 100]"""
import re
import sys
from collections import Counter
rpt = sys.argv[1]; G = float(sys.argv[2]) if len(sys.argv) > 2 else 100.0
T, L, Bn, N = Counter(), Counter(), Counter(), Counter()
typ = None; srcs = []
for ln in open(rpt):
    s = ln.strip()
    if s.startswith("violation type:"):
        typ = s.split(":", 1)[1].strip(); srcs = []
    elif s.startswith("srcs:"):
        srcs = s[5:].split()
    elif s.startswith("bbox"):
        m = re.search(r"\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*-\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*on Layer\s*(\S+)", s)
        if not m: continue
        x1, y1, x2, y2 = map(float, m.groups()[:4]); lay = m.group(5)
        T[typ] += 1; L[lay] += 1; Bn[(int((x1 + x2) / 2 // G * G), int((y1 + y2) / 2 // G * G))] += 1
        for x in srcs:
            k = x.split(":", 1)[-1]; k = re.sub(r"\d+", "#", k)[:40]; N[k] += 1
print("R39DRC total", sum(T.values()), "types", dict(T.most_common(8)))
print("R39DRC layers", dict(L.most_common(12)))
print("R39DRC bins (x y count):", " ".join("%d,%d:%d" % (k[0], k[1], v) for k, v in Bn.most_common(15)))
print("R39DRC sources", dict(N.most_common(12)))
