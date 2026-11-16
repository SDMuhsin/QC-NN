#!/usr/bin/env python3
"""R12 Q3b: who uses the band's horizontal capacity - band H guide demand (M3/M5/M7/M9, GRT-calibrated per layer
from q3.py's factors) by the net's x-span and by the x-span of its repair tree, + the H demand vs capacity profile
across vertical cuts (results/r12.md).
    python3 -I q3b.py <route.guide> <q3_layers.txt> <dumpdb.txt> <r12_dump_init.txt> <ybot> <outdir> [<netcls2.txt> <ovf10.py>]
Net x-span = extent of its guides.  Tree = the net's root (driver walked back through added repair buffers, as q1.py):
tree x-span = union of the extents of all nets of the tree (the logical connection's span before buffering)."""
import os, re, sys
from collections import defaultdict
fg, fq3, fdb, finit, ybot, od = sys.argv[1:7]; ybot = float(ybot)
KD = {}
for ln in open(fq3):
    if ln.startswith("# calibration applied"):
        d = ln.split("dem x")[1].split(); KD = {d[i]: float(d[i + 1]) for i in range(0, len(d), 2)}
HL = ("M3", "M5", "M7", "M9"); G = 3.0; u = 2000.0; HH = float(os.environ.get("QB12_H", "1751"))
init = set(l.split()[1] for l in open(finit) if l.startswith("I "))
span = {}; hd = defaultdict(float); prof = defaultdict(float)
net = None
for ln in open(fg):
    t = ln.split()
    if len(t) == 1 and t[0] not in "()": net = t[0]; continue
    if len(t) != 5: continue
    x0, y0, x1, y1 = (float(v) / u for v in t[:4])
    s = span.get(net)
    span[net] = (min(s[0], x0), max(s[1], x1)) if s else (x0, x1)
    if t[4] in HL and (y0 + y1) / 2 >= ybot:
        n = max(1, round((x1 - x0) / G)) * max(1, round((y1 - y0) / G)) * KD.get(t[4], 1.0)
        hd[net] += n
        for i in range(int(x0 // G), int(x0 // G) + max(1, round((x1 - x0) / G))): prof[i // 10] += KD.get(t[4], 1.0) * max(1, round((y1 - y0) / G))
# tree roots
drv = {}; outn = defaultdict(list)
for ln in open(fdb):
    if not ln.startswith("N "): continue
    t = ln.split(); drv[t[1]] = t[2]
    if t[2] != "-" and not t[2].startswith("PORT:"): outn[t[2].rsplit(":", 1)[0]].append(t[1])
inn = {}
for ln in open(fdb):
    if not ln.startswith("N "): continue
    t = ln.split()
    for s in t[3:]: inn.setdefault(s.rsplit(":", 1)[0], t[1])
def root(n, k=0):
    d = drv.get(n, "-")
    if d == "-" or d.startswith("PORT:") or k > 60: return n
    i = d.rsplit(":", 1)[0]
    if i in init: return n
    p = inn.get(i); return root(p, k + 1) if p else n
tsp = {}
for n, s in span.items():
    r = root(n); a = tsp.get(r); tsp[r] = (min(a[0], s[0]), max(a[1], s[1])) if a else s
tot = sum(hd.values())
CAPG = 0.0
for ln in open(fq3):
    t = ln.split()
    if len(t) > 3 and t[0] in HL and t[1] == 'H': CAPG += float(t[-1]) * 1e6
CAPG /= (1330 * ((HH - ybot) // G))
bins = [(0, 50), (50, 390), (390, 1000), (1000, 2000), (2000, 1e9)]
L = ["# R12 Q3b band (y >= %.0f) H demand (M3+M5+M7+M9, calibrated %s): total %.3f M track-gcells" % (ybot, " ".join("%s %.3f" % (k, KD.get(k, 1)) for k in HL), tot / 1e6)]
L.append("# by net x-span (um) | by tree x-span (logical connection, through repair buffers)")
for lo, hi in bins:
    a = sum(v for n, v in hd.items() if lo <= span[n][1] - span[n][0] < hi)
    b = sum(v for n, v in hd.items() if lo <= tsp[root(n)][1] - tsp[root(n)][0] < hi)
    L.append("SPAN %5d-%-6.0f net %5.1f %% | tree %5.1f %%" % (lo, min(hi, 99999), 100 * a / tot, 100 * b / tot))
L.append("# band H capacity (q3 model, calibrated) %.1f tracks per gcell" % CAPG)
L.append("# H demand per 30-um x slice of the band (calibrated track-gcells / gcell rows = mean tracks used per band row-gcell), every 4th slice")
rows = (HH - ybot) / G
for k in sorted(prof)[::4]: L.append("X %5.0f %6.1f" % (k * 30, prof[k] / 10 / rows))
# vertical-cut crossings in the band: H guides crossing x = cut, by root class (impl/r10b/ovf10.py grp) and tree span
if len(sys.argv) > 8:
    import ast
    fn = [n for n in ast.parse(open(sys.argv[8]).read()).body if isinstance(n, ast.FunctionDef) and n.name == "grp"][0]
    ns = {}; exec(compile(ast.Module(body=[fn], type_ignores=[]), sys.argv[8], "exec"), ns); grp = ns["grp"]
    cls = {}
    for ln in open(sys.argv[7]):
        t = ln.split()
        if len(t) >= 2: cls[t[0]] = t[1]
    cuts = (650, 1055, 1445, 1835, 2225, 2615, 3005, 3395, 3785)
    C = {c: defaultdict(float) for c in cuts}; S = {c: defaultdict(float) for c in cuts}
    net = None
    for ln in open(fg):
        t = ln.split()
        if len(t) == 1 and t[0] not in "()": net = t[0]; continue
        if len(t) != 5 or t[4] not in HL: continue
        x0, y0, x1, y1 = (float(v) / u for v in t[:4])
        if (y0 + y1) / 2 < ybot: continue
        for c in cuts:
            if x0 < c < x1:
                w = KD.get(t[4], 1.0) * max(1, round((y1 - y0) / G))
                C[c][grp(cls.get(net, "unknown"))] += w
                sp = tsp[root(net)][1] - tsp[root(net)][0]
                S[c]["<390" if sp < 390 else "390-1000" if sp < 1000 else ">=1000"] += w
    capc = CAPG * ((HH - ybot) // G)
    L.append("# band H crossings of vertical cuts (calibrated tracks) vs H capacity across the band height %.0f tracks" % capc)
    for c in cuts:
        tc = sum(C[c].values())
        L.append("CUT x %4d crossings %5.0f (%3.0f %% of cap) | tree span %s | top classes %s" % (c, tc, 100 * tc / capc,
                 " ".join("%s %.0f%%" % (k, 100 * S[c][k] / max(1, tc)) for k in ("<390", "390-1000", ">=1000")),
                 ", ".join("%s %.0f%%" % (k, 100 * v / tc) for k, v in sorted(C[c].items(), key=lambda kv: -kv[1])[:5])))
open(od + "/q3b_span.txt", "w").write("\n".join(L) + "\n"); print("\n".join(L))
