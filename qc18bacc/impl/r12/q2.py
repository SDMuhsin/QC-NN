#!/usr/bin/env python3
"""R12 Q2: std-cell utilisation vs GRT overflow in the logic band (results/r12.md).
    python3 -I q2.py <r12_dump.txt> <dumpdb.txt> <gr_congestion.rpt> <ybot> <outdir> [bin_gcells 17]
Bins of n x n gcells (3 um); util = std-cell area (by centre) / placement-row area in the bin; overflow fraction = overflowed
gcells (H or V) / gcells.  Pins per gcell = std-cell pins counted at the cell centre + block ports (approximation of
pin location, [E])."""
import re, sys
from collections import Counter, defaultdict
fdump, fdb, frpt, ybot, od = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), sys.argv[5]
nb = int(sys.argv[6]) if len(sys.argv) > 6 else 17
G = 3.0; B = G * nb
A = {}; I = {}; rows = []; ports = {}
for ln in open(fdump):
    t = ln.split()
    if t[0] == "M": A[t[1]] = float(t[2])
    elif t[0] == "I": I[t[1]] = (t[2], float(t[3]), float(t[4]))
    elif t[0] == "R": rows.append(tuple(map(float, t[1:5])))
    elif t[0] == "P": ports[t[1]] = (float(t[2]), float(t[3]))
gk = lambda x, y: (int(x // G), int(y // G))
bk = lambda x, y: (int(x // B), int(y // B))
cap = Counter()
for x0, y0, x1, y1 in rows:
    if y1 <= ybot: continue
    y0 = max(y0, ybot)
    i = int(x0 // B)
    while i * B < x1:
        ov = min(x1, (i + 1) * B) - max(x0, i * B)
        j = int(y0 // B)
        while j * B < y1:
            oy = min(y1, (j + 1) * B) - max(y0, j * B)
            if ov > 0 and oy > 0: cap[(i, j)] += ov * oy
            j += 1
        i += 1
use = Counter(); gpins = Counter(); garea = Counter()
for n, (m, x, y) in I.items():
    a = A.get(m, 0)
    if a > 1000 or y < ybot: continue
    use[bk(x, y)] += a; garea[gk(x, y)] += a
for ln in open(fdb):
    if not ln.startswith("N "): continue
    for p in ln.split()[2:]:
        if p == "-": continue
        if p.startswith("PORT:"):
            q = ports.get(p[5:])
        else:
            i = I.get(p.rsplit(":", 1)[0]); q = (i[1], i[2]) if i and A.get(i[0], 0) <= 1000 else None
        if q and q[1] >= ybot: gpins[gk(*q)] += 1
ov = defaultdict(lambda: [0, 0, 0, 0])   # gcell -> H ovf, V ovf, H cap, V cap
cur = None
for ln in open(frpt):
    s = ln.strip()
    if s.startswith("violation type"): d = 0 if "Horizontal" in s else 1
    elif s.startswith("congestion information"):
        c, u, o = map(int, re.search(r"capacity:(\d+) usage:(\d+) overflow:(\d+)", s).groups())
    elif s.startswith("bbox"):
        x1, y1, x2, y2 = map(float, re.search(r"\(\s*([\d.]+),\s*([\d.]+)\s*\)\s*-\s*\(\s*([\d.]+),\s*([\d.]+)\)", s).groups())
        k = gk((x1 + x2) / 2, (y1 + y2) / 2)
        if (y1 + y2) / 2 >= ybot: ov[k][d] += o; ov[k][2 + d] = c
bo = Counter(); bH = Counter()
for k, v in ov.items():
    b = (k[0] // nb, k[1] // nb); bo[b] += 1; bH[b] += v[0]
L = ["# R12 Q2 band y >= %.0f: %d-um bins (util = std area / row area), bins with row area >= 25 %% of the bin" % (ybot, B)]
X = []
for b, c in cap.items():
    if c < 0.25 * B * B: continue
    X.append((use[b] / c, bo[b] / float(nb * nb), bH[b], b))
n = len(X)
mx = sum(x[0] for x in X) / n; my = sum(x[1] for x in X) / n
cov = sum((x[0] - mx) * (x[1] - my) for x in X); vx = sum((x[0] - mx) ** 2 for x in X); vy = sum((x[1] - my) ** 2 for x in X)
L.append("bins %d, mean util %.3f, mean overflowed-gcell fraction %.3f, Pearson r(util, ovf frac) = %.3f" % (n, mx, my, cov / (vx * vy) ** 0.5))
rk = lambda v: {i: r for r, i in enumerate(sorted(range(len(v)), key=lambda i: v[i]))}
ra, rb = rk([x[0] for x in X]), rk([x[1] for x in X])
L.append("Spearman rho = %.3f" % (1 - 6 * sum((ra[i] - rb[i]) ** 2 for i in range(n)) / (n * (n * n - 1.0))))
edges = [0, .5, .6, .7, .8, .85, .9, .95, 1.0, 9]
L.append("# util histogram: bins clean (0 ovf gcells) | bins hot (>= 30 % gcells ovf) | mean ovf frac | H ovf tracks")
for lo, hi in zip(edges, edges[1:]):
    s = [x for x in X if lo <= x[0] < hi]
    L.append("UTIL %.2f-%.2f  all %4d  clean %4d  hot %4d  mean_ovf %.3f  Hovf %7d" % (lo, hi, len(s), sum(1 for x in s if x[1] == 0), sum(1 for x in s if x[1] >= .3), sum(x[1] for x in s) / max(1, len(s)), sum(x[2] for x in s)))
for thr in (.8, .85, .9):
    hi = [x for x in X if x[0] >= thr]; lo = [x for x in X if x[0] < thr]
    L.append("util >= %.2f: %d bins mean ovf %.3f | < %.2f: %d bins mean ovf %.3f" % (thr, len(hi), sum(x[1] for x in hi) / max(1, len(hi)), thr, len(lo), sum(x[1] for x in lo) / max(1, len(lo))))
# x-profile: per 390-um column region (x0 860)
L.append("# per region: mean util, mean ovf frac")
reg = lambda x: "west" if x < 860 else "col%d" % min(7, int((x - 860) // 390))
R = defaultdict(list)
for x in X: R[reg((x[3][0] + .5) * B)].append(x)
for k in ["west"] + ["col%d" % i for i in range(8)]:
    s = R[k]; L.append("REG %-5s bins %3d util %.3f ovf %.3f" % (k, len(s), sum(x[0] for x in s) / max(1, len(s)), sum(x[1] for x in s) / max(1, len(s))))
# per region group util hist: bins / mean ovf
X6 = [x for x in X if reg((x[3][0] + .5) * B) == "col6"]; X05 = [x for x in X if reg((x[3][0] + .5) * B) in ["col%d" % i for i in range(6)]]
for lo, hi in ((0, .9), (.9, .95), (.95, 1.0), (1.0, 9)):
    a = [x for x in X6 if lo <= x[0] < hi]; b = [x for x in X05 if lo <= x[0] < hi]
    L.append("UTILREG %.2f-%.2f col6 bins %3d ovf %.3f | col0-5 bins %3d ovf %.3f" % (lo, hi, len(a), sum(x[1] for x in a) / max(1, len(a)), len(b), sum(x[1] for x in b) / max(1, len(b))))
L.append("# pins per gcell (3 um, cell centres; all band gcells incl. over macros) vs overflow: gcells, overflowed (H or V), H ovf tracks, V ovf tracks")
H = max(r[3] for r in rows)
allg = {(i, j) for i in range(int(3990 // G)) for j in range(int(ybot // G) + 1, int(H // G))}
for lo, hi in ((0, 0), (1, 4), (5, 9), (10, 14), (15, 19), (20, 29), (30, 999)):
    s = [g for g in allg if lo <= gpins[g] <= hi]
    L.append("PINS %3d-%-3d gcells %7d ovf %7d (%5.1f %%) Hovf %7d Vovf %7d" % (lo, hi, len(s), sum(1 for g in s if g in ov), 100.0 * sum(1 for g in s if g in ov) / max(1, len(s)), sum(ov[g][0] for g in s if g in ov), sum(ov[g][1] for g in s if g in ov)))
open(od + "/q2_density.txt", "w").write("\n".join(L) + "\n"); print("\n".join(L))
# per-bin table for plotting (x y util ovf)
with open(od + "/q2_bins.txt", "w") as f:
    for u, o, h, b in sorted(X, key=lambda x: x[3]): f.write("%d %d %.3f %.3f %d\n" % (b[0] * B, b[1] * B, u, o, h))
