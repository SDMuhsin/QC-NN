#!/usr/bin/env python3
"""R11: top GRT overflow by region (record format of OpenROAD's -congestion_report_file, as impl/r10b/ovf10.py).
    python3 -I ovf11.py <gr_congestion.rpt> <run mplace.tcl> [die W 3990] [die H]
Regions (chip um, fp11.py): hub (y < yh), array (x >= 860, yh <= y < yt), act (act block box), gap (x < 860,
yh <= y < act bottom: hub -> act S / map port wiring + top cells), NWcorner (x < 860 and y >= act top), north
(x >= 860, y >= yt: band + weight rows).  Per region: overflowed gcells / gcells, overflow tracks H / V, and the
most frequent source-net name stems."""
import re
import sys
from collections import Counter, defaultdict

rpt, mpl = sys.argv[1:3]
t = open(mpl).read()
W, H = map(float, re.search(r"P\(DIE_AREA\) \{0 0 ([\d.]+) ([\d.]+)\}", t).groups())
yh = float(re.search(r"QB11_YH ([\d.]+)", t).group(1)); yt = float(re.search(r"QB11_YT ([\d.]+)", t).group(1))
ax1, ay1, ax2, ay2 = map(float, re.search(r"QB11_ACT \{([^}]*)\}", t).group(1).split())
def reg(x, y):
    if y < yh: return "hub"
    if ax1 <= x < ax2 and ay1 <= y < ay2: return "act"
    if x >= 860 and y < yt: return "array"
    if x < 860 and y < ay1: return "gap"
    if x < 860: return "NWcorner"
    return "north"
area = {"hub": W * yh, "array": (W - 860) * (yt - yh), "act": (ax2 - ax1) * (ay2 - ay1), "gap": 860 * (ay1 - yh),
        "NWcorner": 860 * (H - yt) + (860 - ax2 + ax1 - 0) * 0, "north": (W - 860) * (H - yt)}
area["NWcorner"] = 860 * (H - ay2) + ax1 * (ay2 - ay1) - 0
recs, cur = [], None
for ln in open(rpt):
    s = ln.strip()
    if s.startswith("violation type"):
        cur = {"d": "H" if "Horizontal" in s else "V", "nets": []}
    elif s.startswith("srcs:") and cur is not None:
        cur["nets"] = [x[4:] if x.startswith("net:") else x for x in s[5:].split()]
    elif s.startswith("congestion information") and cur is not None:
        m = re.search(r"capacity:(\d+) usage:(\d+) overflow:(\d+)", s)
        cur["cap"], cur["use"], cur["ov"] = map(int, m.groups())
    elif s.startswith("bbox") and cur is not None:
        m = re.search(r"\(\s*([\d.]+),\s*([\d.]+)\s*\)\s*-\s*\(\s*([\d.]+),\s*([\d.]+)\)", s)
        x1, y1, x2, y2 = map(float, m.groups())
        cur["x"], cur["y"], cur["g"] = (x1 + x2) / 2, (y1 + y2) / 2, x2 - x1
        ly = re.search(r"[Ll]ayer\s*(\S+)", s)
        cur["ly"] = ly.group(1) if ly else "-"
        recs.append(cur); cur = None
g = recs[0]["g"] if recs else 3.0
R = defaultdict(lambda: [set(), 0, 0, Counter()])
L = Counter()
for r in recs:
    k = reg(r["x"], r["y"]); e = R[k]
    e[0].add((round(r["x"], 1), round(r["y"], 1)))
    e[1 if r["d"] == "H" else 2] += r["ov"]
    L[(r["d"], r["ly"])] += r["ov"]
    for n in r["nets"]:
        e[3][re.sub(r"(\[\d+\]|_\d+_?|\d+)+$", "", n.replace("\\", ""))] += 1
allc = set().union(*[e[0] for e in R.values()]) if R else set()
print("OVF11 gcell %.1f um; overflowed gcells %d of %d = %.2f %%; overflow H %d V %d tracks"
      % (g, len(allc), int(W / g) * int(H / g), 100.0 * len(allc) / max(1, int(W / g) * int(H / g)),
         sum(e[1] for e in R.values()), sum(e[2] for e in R.values())))
print("%-9s %9s %8s %9s %9s  %s" % ("region", "ovf_gcell", "%region", "ovf_H", "ovf_V", "top source-net stems"))
for k in ("hub", "array", "act", "gap", "NWcorner", "north"):
    e = R.get(k, [set(), 0, 0, Counter()])
    n = area[k] / (g * g)
    print("%-9s %9d %7.2f%% %9d %9d  %s" % (k, len(e[0]), 100.0 * len(e[0]) / max(1, n), e[1], e[2],
                                           ", ".join("%s %d" % x for x in e[3].most_common(5))))
if any(ly != "-" for _, ly in L):
    print("by direction / layer: " + ", ".join("%s %s %d" % (d, ly, v) for (d, ly), v in sorted(L.items())))
