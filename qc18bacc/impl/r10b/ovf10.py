#!/usr/bin/env python3
"""R10b: impl/r9b/ovf9.py + per family the overflowed gcells left (%% of all gcells) + y regions (QB_YS: S rows
bottom/top, default 361 1300).
R9b: hub GRT overflow by x-region and by traffic class, + what-if removal of each class (analytic).
    python3 -I ovf9.py <gr_congestion.rpt> <netcls.txt> <openroad.log> [x0 860] [die_w 3990] [die_h 1700.6]
Regions: west strip x < x0 (act-block side), col0..col7 = x0 + 390 c (under column c).  A gcell record = one direction.
Per record capacity / usage / overflow and its source nets; a net counts one track (class = its root driver, netcls.tcl).
What-if: overflow after removing class K = sum over records of max(0, usage - n_K - capacity) (no rerouting; lower bound
of the effect's size only for nets that would leave the region; an RTL change that shortens the class's wires)."""
import re
import sys
from collections import Counter, defaultdict

rpt, ncf, log = sys.argv[1:4]
x0 = float(sys.argv[4]) if len(sys.argv) > 4 else 860.0
W = float(sys.argv[5]) if len(sys.argv) > 5 else 3990.0
H = float(sys.argv[6]) if len(sys.argv) > 6 else 1700.6
ncls = {}
for ln in open(ncf):
    f = ln.split()
    if len(f) >= 2:
        ncls[f[0]] = f[1]
def grp(c):
    if c.startswith("glue:") or c.startswith("fyreg>"):
        return c
    if c.startswith("reg:u_top_g_wbq_fyq") or c.startswith("PORT:u_top_f_y") or "fy" in c:
        return "f_y path"
    for k in ("MACRO:qb_p", "MACRO:qb_s", "MACRO:qb_b", "MACRO:qb_i", "MACRO:qb_f"):
        if c.startswith(k):
            return k + " Q"
    if c.startswith("PORT:"):
        return "port in (" + c[5:] + ")" if False else "port in"
    if c.startswith("reg:"):
        return "glue regs"
    return c.split(":")[0]
recs = []
cur = None
for ln in open(rpt):
    s = ln.strip()
    if s.startswith("violation type"):
        cur = {"d": "H" if "Horizontal" in s else "V"}
    elif s.startswith("srcs:"):
        cur["nets"] = [t[4:].replace("\\", "") for t in s[5:].split()]
    elif s.startswith("congestion information"):
        m = re.search(r"capacity:(\d+) usage:(\d+) overflow:(\d+)", s)
        cur["cap"], cur["use"], cur["ov"] = map(int, m.groups())
    elif s.startswith("bbox"):
        m = re.search(r"\(\s*([\d.]+),\s*([\d.]+)\s*\)\s*-\s*\(\s*([\d.]+),\s*([\d.]+)\)", s)
        x1, y1, x2, y2 = map(float, m.groups())
        cur["x"], cur["y"], cur["g"] = (x1 + x2) / 2, (y1 + y2) / 2, x2 - x1
        recs.append(cur)
g = recs[0]["g"] if recs else 3.0
ntot = int(W / g) * int(H / g)
reg = lambda x: "west" if x < x0 else "col%d" % min(7, int((x - x0) // 390))
out = []
cells = set((round(r["x"], 1), round(r["y"], 1)) for r in recs)
out.append("gcell %.1f um; overflowed gcells %d of %d = %.2f %%; records H %d V %d; total overflow H %d V %d tracks"
           % (g, len(cells), ntot, 100.0 * len(cells) / ntot, sum(r["d"] == "H" for r in recs), sum(r["d"] == "V" for r in recs),
              sum(r["ov"] for r in recs if r["d"] == "H"), sum(r["ov"] for r in recs if r["d"] == "V")))
R = defaultdict(lambda: [set(), 0, 0])
for r in recs:
    k = reg(r["x"]); R[k][0].add((round(r["x"], 1), round(r["y"], 1)))
    R[k][1 if r["d"] == "H" else 2] += r["ov"]
for k in ["west"] + ["col%d" % c for c in range(8)]:
    w = (x0 if k == "west" else 390.0)
    n = int(w / g) * int(H / g)
    out.append("REGION %-5s overflowed gcells %6d = %5.1f %% of region; overflow H %6d V %6d tracks" % (k, len(R[k][0]), 100.0 * len(R[k][0]) / n, R[k][1], R[k][2]))
# classes in overflowed records (share of track usage) and what-if
CU = Counter(); CR = Counter()
per = []
for r in recs:
    cc = Counter(grp(ncls.get(n, "unknown")) for n in r["nets"])
    per.append((r, cc))
    for k, v in cc.items():
        CU[k] += v
tot = sum(CU.values())
base = sum(r["ov"] for r in recs)
out.append("# class: share of net-tracks in overflowed gcells | overflow left if the class's tracks vanished (of %d)" % base)
for k, v in CU.most_common(14):
    left = sum(max(0, r["use"] - cc.get(k, 0) - r["cap"]) for r, cc in per)
    out.append("CLASS %-22s %5.1f %% | overflow left %6d (%5.1f %% of base)" % (k, 100.0 * v / tot, left, 100.0 * left / max(1, base)))
# RTL traffic families (several classes removed together)
FAM = [("write-back (f_y regs -> rotators -> S/B write)", ("fyreg>s-in", "glue:fy-reg>s-in", "glue:reg>s-in", "f_y path")),
       ("S-read -> act port (S Q + rotator)", ("MACRO:qb_s Q", "glue:s-Q>act-out", "glue:b-Q>act-out", "MACRO:qb_b Q")),
       ("params Q -> pf / pw", ("MACRO:qb_p Q",)),
       ("write-back + S-read", ("fyreg>s-in", "glue:fy-reg>s-in", "glue:reg>s-in", "f_y path", "MACRO:qb_s Q", "glue:s-Q>act-out", "glue:b-Q>act-out", "MACRO:qb_b Q")),
       ("all three", ("fyreg>s-in", "glue:fy-reg>s-in", "glue:reg>s-in", "f_y path", "MACRO:qb_s Q", "glue:s-Q>act-out", "glue:b-Q>act-out", "MACRO:qb_b Q", "MACRO:qb_p Q"))]
for name, ks in FAM:
    left = sum(max(0, r["use"] - sum(cc.get(k, 0) for k in ks) - r["cap"]) for r, cc in per)
    cells_left = sum(1 for r, cc in per if r["use"] - sum(cc.get(k, 0) for k in ks) > r["cap"])
    gc_left = len(set((round(r["x"], 1), round(r["y"], 1)) for r, cc in per if r["use"] - sum(cc.get(k, 0) for k in ks) > r["cap"]))
    out.append("FAMILY %-48s share %5.1f %% | overflow left %6d (%5.1f %%), overflowed records left %d of %d, gcells %.2f %%"
               % (name, 100.0 * sum(CU.get(k, 0) for k in ks) / tot, left, 100.0 * left / max(1, base), cells_left, len(recs), 100.0 * gc_left / ntot))
import os
ys = [float(v) for v in os.environ.get("QB_YS", "361 1300").split()]
for nm, lo, hi in (("south (params/B) y<%g" % ys[0], -1, ys[0]), ("S rows y %g-%g" % tuple(ys), ys[0], ys[1]), ("band y>%g" % ys[1], ys[1], 1e9)):
    for d in "HV":
        out.append("YREGION %-26s %s overflow %7d tracks, overflowed gcells %d" % (nm, d, sum(r["ov"] for r in recs if r["d"] == d and lo <= r["y"] < hi),
                   len(set((round(r["x"], 1), round(r["y"], 1)) for r in recs if r["d"] == d and lo <= r["y"] < hi))))
# per-layer table from the GRT log
lay = []
for ln in open(log):
    if re.match(r"^M\d\s+\|?", ln.strip()) and ("%" in ln):
        lay.append("LAYER " + " ".join(ln.split()))
out += lay[-9:]
print("\n".join(out))
