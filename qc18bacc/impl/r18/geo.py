#!/usr/bin/env python3
"""R18 (results/r18.md): physical arrangement of qb_act2_blk cell classes (impl/r18/dump.tcl cells.txt + nets.txt).
    python3 -I geo.py <cells.txt> <nets.txt>
Per class: count, area, x / y percentiles (p5 / p50 / p95, um), x width actually used (p5..p95) vs the 900-um die, and the
share of 10-um x columns holding >= 0.5 % of the class's area.  Buffers (BUFF / INV / CKBD / CKND / DEL outside the named
classes) are attributed to the class of the net they drive (cls18).  Per act row: centroids of act regs, S1 regs, S1 / S2 comb.
Per (ctx, slot): lb flop centroids; per slot: pre-mux centroids."""
import sys, os, collections as C
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import cls18
fc, fn = sys.argv[1:3]
NC = cls18.load(fn)
P = C.defaultdict(list)    # class -> [(x, y, area)]
ROW = C.defaultdict(lambda: C.defaultdict(list)); SL = C.defaultdict(list); PM = C.defaultdict(list)
CN = {"lbff": "lb flops", "lbc": "lb comb (D-mux)", "pm": "pre-mux", "s1ff": "S1 regs", "s1c": "S1 comb", "s2ff": "act regs (S2)",
      "s2c": "S2 comb", "wdq": "rdq/sdq regs", "apipe": "act edge flops", "dist": "dist regs", "clk": "clock tree", "ff": "other ff", "comb": "other comb"}
for ln in open(fc):
    t = ln.split()
    c, x, y, w, h, tag, nm, on = t[0], float(t[1]), float(t[2]), float(t[3]), float(t[4]), t[5], t[6], t[7]
    if c == "buf": k = "buf -> " + NC.get(on, "other")
    elif c.startswith("sel:"): k = "select regs"
    else: k = CN.get(c, c)
    P[k].append((x, y, w * h))
    if c in ("s1ff", "s1c", "s2ff", "s2c") and tag not in ("-", "-1"): ROW[int(tag)][c].append((x, y))
    if c == "lbff" and tag != "-":
        cc, s, b = tag.split("."); SL[(int(cc), int(s))].append((x, y))
    if c == "pm" and tag != "-": PM[int(tag.split(".")[0])].append((x, y))
print("# class  n  area(um2)  x p5 p50 p95  width(p5-p95)  x-cols>=0.5%%  |  y p5 p50 p95")
for k in sorted(P, key=lambda k: -sum(a for _, _, a in P[k])):
    a = np.array(P[k]); x, y, ar = a[:, 0], a[:, 1], a[:, 2]
    if ar.sum() < 2000: continue
    hx = np.bincount((x // 10).astype(int), weights=ar, minlength=90)
    px = np.percentile(x, [5, 50, 95]); py = np.percentile(y, [5, 50, 95])
    print("CLS %-28s %6d %8.0f  x %4.0f %4.0f %4.0f  w %4.0f  %4.0f %%  |  y %5.0f %5.0f %5.0f" % (k, len(x), ar.sum(), *px, px[2] - px[0], 100.0 * (hx >= 0.005 * ar.sum()).mean(), *py))
print("# per act row: act regs (x, y) | S1 regs (x, y, sd y) | S1 comb (x p5-p95, y p50, sd y) | S2 comb (y p50)")
for r in sorted(ROW):
    d = ROW[r]
    def m(c): a = np.array(d[c]) if d[c] else np.zeros((1, 2)); return a
    a2, a1, c1, c2 = m("s2ff"), m("s1ff"), m("s1c"), m("s2c")
    print("ROW %2d act %4.0f %5.0f | S1 %4.0f %5.0f sd %4.0f | S1c n %5d x %4.0f-%4.0f y %5.0f sd %4.0f | S2c y %5.0f" % (
        r, a2[:, 0].mean(), a2[:, 1].mean(), a1[:, 0].mean(), a1[:, 1].mean(), a1[:, 1].std(), len(d["s1c"]),
        np.percentile(c1[:, 0], 5), np.percentile(c1[:, 0], 95), np.median(c1[:, 1]), c1[:, 1].std(), np.median(c2[:, 1])))
print("# lb flops per (ctx, slot): n, x mean / p5-p95, y mean / p5-p95")
for k in sorted(SL):
    a = np.array(SL[k])
    print("LB c%d s%d %5d x %4.0f %4.0f-%4.0f y %5.0f %5.0f-%5.0f" % (k[0], k[1], len(a), a[:, 0].mean(), *np.percentile(a[:, 0], [5, 95]), a[:, 1].mean(), *np.percentile(a[:, 1], [5, 95])))
print("# pre-mux per slot (from its fan-in lb flop)")
for s in sorted(PM):
    a = np.array(PM[s])
    print("PM s%d %5d x %4.0f %4.0f-%4.0f y %5.0f %5.0f-%5.0f" % (s, len(a), a[:, 0].mean(), *np.percentile(a[:, 0], [5, 95]), a[:, 1].mean(), *np.percentile(a[:, 1], [5, 95])))
