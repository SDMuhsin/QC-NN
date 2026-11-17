#!/usr/bin/env python3
"""R14: top GRT overflow by region (OpenROAD -congestion_report_file records, as impl/r11/ovf11.py) for the fp14.py
floorplan: hub (y < yh), act (act box), array (x >= X0, yh..yt), gap (x < X0, yh..act bottom), NWcorner (x < X0,
y >= yt), north (x >= X0, y >= yt).  Per region: overflowed gcells / gcells (3-um gcells), overflow tracks H / V, top
source-net stems.
    python3 -I ovf14.py <gr_congestion.rpt> <run mplace.tcl> [gcell um 3.0]"""
import re
import sys
from collections import Counter, defaultdict

rpt, mpl = sys.argv[1:3]
G = float(sys.argv[3]) if len(sys.argv) > 3 else 3.0
t = open(mpl).read()
W, H = map(float, re.search(r"P\(DIE_AREA\) \{0 0 ([\d.]+) ([\d.]+)\}", t).groups())
yh = float(re.search(r"QB11_YH ([\d.]+)", t).group(1)); yt = float(re.search(r"QB11_YT ([\d.]+)", t).group(1))
ax1, ay1, ax2, ay2 = map(float, re.search(r"QB11_ACT \{([^}]*)\}", t).group(1).split())
X0 = float(re.search(r"QB14_X0 ([\d.]+)", t).group(1))
def reg(x, y):
    if y < yh: return "hub"
    if ax1 <= x < ax2 and ay1 <= y < ay2: return "act"
    if x >= X0 and y < yt: return "array"
    if x < X0 and y < ay1: return "gap"
    if x < X0: return "NWcorner"
    return "north"
area = {"hub": W * yh, "act": (ax2 - ax1) * (ay2 - ay1), "array": (W - X0) * (yt - yh), "gap": X0 * (ay1 - yh),
        "NWcorner": X0 * (H - yt), "north": (W - X0) * (H - yt)}
recs, cur = [], None
for ln in open(rpt):
    s = ln.strip()
    if s.startswith("violation type"):
        cur = {"d": "H" if "Horizontal" in s else "V", "nets": []}
    elif s.startswith("srcs:") and cur is not None:
        cur["nets"] = [x[4:] if x.startswith("net:") else x for x in s[5:].split()]
    elif s.startswith("congestion information") and cur is not None:
        m = re.search(r"capacity:(\d+) usage:(\d+) overflow:(\d+)", s)
        cur["ov"] = int(m.group(3))
    elif s.startswith("bbox") and cur is not None:
        m = re.search(r"\(\s*([\d.]+),\s*([\d.]+)\s*\)\s*-\s*\(\s*([\d.]+),\s*([\d.]+)\)", s)
        x1, y1, x2, y2 = map(float, m.groups())
        cur["x"], cur["y"] = (x1 + x2) / 2, (y1 + y2) / 2
        recs.append(cur); cur = None
R = defaultdict(lambda: [set(), 0, 0, Counter()])
for r in recs:
    e = R[reg(r["x"], r["y"])]
    e[0].add((round(r["x"], 1), round(r["y"], 1)))
    e[1 if r["d"] == "H" else 2] += r.get("ov", 0)
    for n in r["nets"]:
        e[3][re.sub(r"(\[\d+\]|_\d+_?|\d+)+$", "", n.replace("\\", ""))] += 1
allc = set().union(*[e[0] for e in R.values()]) if R else set()
totg = int(W / G) * int(H / G)
print("OVF14 overflowed gcells %d of %d = %.3f %%; overflow H %d V %d tracks" % (len(allc), totg, 100.0 * len(allc) / totg,
      sum(e[1] for e in R.values()), sum(e[2] for e in R.values())))
print("%-9s %9s %8s %9s %9s  %s" % ("region", "ovf_gcell", "%region", "ovf_H", "ovf_V", "top source-net stems"))
for k in ("hub", "act", "array", "gap", "NWcorner", "north"):
    e = R.get(k, [set(), 0, 0, Counter()])
    print("%-9s %9d %7.2f%% %9d %9d  %s" % (k, len(e[0]), 100.0 * len(e[0]) / max(1, area[k] / G / G), e[1], e[2],
                                           ", ".join("%s %d" % x for x in e[3].most_common(5))))
