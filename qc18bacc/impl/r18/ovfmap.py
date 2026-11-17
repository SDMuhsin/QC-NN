#!/usr/bin/env python3
"""R18 (results/r18.md): GRT overflow map vs DR marker map of qb_act2_blk.
    python3 -I ovfmap.py <gr_congestion.rpt> <drt.drc.rpt> [bin_um 100]
Overflow per bin = sum of the report's overflow (tracks) of the gcell records whose centre lies in the bin, H / V separately;
markers per bin = DR violation boxes (centre) of any type / M2+M3 shorts.  Prints: overflow-gcell share, x / y profiles,
coarse maps (rows = y bins top-down), and the agreement: Pearson / Spearman over bins and the share of markers inside the
bins holding the top 10 / 20 % of overflow."""
import re, sys, collections as C
import numpy as np
fr, fd = sys.argv[1:3]
B = float(sys.argv[3]) if len(sys.argv) > 3 else 100.0
W, H, G = 900.0, 1970.0, 3.0
nx, ny = int(np.ceil(W / B)), int(np.ceil(H / B))
OV = {"H": np.zeros((nx, ny)), "V": np.zeros((nx, ny))}
cells = set(); rec = C.Counter(); tr = C.Counter()
bb = re.compile(r"\(\s*([-\d.]+),\s*([-\d.]+)\s*\)\s*-\s*\(\s*([-\d.]+),\s*([-\d.]+)\s*\)(?:\s*on Layer (\S+))?")
d = None; ov = 0
for ln in open(fr):
    s = ln.strip()
    if s.startswith("violation type"): d = "H" if "Horizontal" in s else "V"
    elif s.startswith("congestion information"): ov = int(re.search(r"overflow:(\d+)", s).group(1))
    elif s.startswith("bbox"):
        x1, y1, x2, y2 = map(float, bb.search(s).groups()[:4]); x, y = (x1 + x2) / 2, (y1 + y2) / 2
        OV[d][min(nx - 1, int(x // B)), min(ny - 1, int(y // B))] += ov
        cells.add((int(x // G), int(y // G))); rec[d] += 1; tr[d] += ov
ng = int(np.ceil(W / G)) * int(np.ceil(H / G))
print("# GRT report: overflowed gcells %d of %d = %.2f %%; records H %d V %d; overflow tracks H %d V %d" % (len(cells), ng, 100.0 * len(cells) / ng, rec["H"], rec["V"], tr["H"], tr["V"]))
MK = np.zeros((nx, ny)); MS = np.zeros((nx, ny)); typ = None; lay = C.Counter()
for ln in open(fd):
    if "violation type" in ln: typ = ln.split(":", 1)[1].strip()
    elif "bbox" in ln:
        m = bb.search(ln)
        if not m: continue
        x, y = (float(m.group(1)) + float(m.group(3))) / 2, (float(m.group(2)) + float(m.group(4))) / 2
        k = (min(nx - 1, max(0, int(x // B))), min(ny - 1, max(0, int(y // B))))
        MK[k] += 1; lay[(typ, m.group(5))] += 1
        if typ == "Short" and m.group(5) in ("M2", "M3"): MS[k] += 1
print("# DR markers %d, top types: %s" % (MK.sum(), ", ".join("%s/%s %d" % (a, b, v) for (a, b), v in lay.most_common(6))))
T = OV["H"] + OV["V"]
def prof(a, ax): return a.sum(axis=ax)
print("# y profile (bin y0): overflow H, V | markers all, M2+M3 shorts (k)")
for j in range(ny):
    print("YP %5.0f  %7.0f %7.0f | %7.1f %7.1f" % (j * B, OV["H"][:, j].sum(), OV["V"][:, j].sum(), MK[:, j].sum() / 1e3, MS[:, j].sum() / 1e3))
print("# x profile (bin x0): overflow H, V | markers all, M2+M3 shorts (k)")
for i in range(nx):
    print("XP %5.0f  %7.0f %7.0f | %7.1f %7.1f" % (i * B, OV["H"][i].sum(), OV["V"][i].sum(), MK[i].sum() / 1e3, MS[i].sum() / 1e3))
def mp(name, a, sc):
    print("# map %s (x bins left->right, y top-down), units %s" % (name, sc[1]))
    for j in range(ny - 1, -1, -1):
        print("MAP %-7s %5.0f " % (name, j * B) + " ".join("%5.0f" % (a[i, j] / sc[0]) for i in range(nx)))
mp("ovf", T, (1, "tracks")); mp("mk", MK, (1e3, "k markers"))
def rank(v): r = np.empty(len(v)); r[np.argsort(v)] = np.arange(len(v)); return r
a, b = T.ravel(), MK.ravel()
print("AGREE Pearson ovf~markers %.3f, Spearman %.3f; ovf~M2/M3 shorts Pearson %.3f" % (np.corrcoef(a, b)[0, 1], np.corrcoef(rank(a), rank(b))[0, 1], np.corrcoef(a, MS.ravel())[0, 1]))
o = np.argsort(-a)
for f in (0.1, 0.2):
    k = o[:max(1, int(f * len(a)))]
    print("AGREE top %2.0f %% overflow bins hold %.1f %% of overflow and %.1f %% of markers (%.1f %% of M2/M3 shorts)" % (100 * f, 100 * a[k].sum() / max(1, a.sum()), 100 * b[k].sum() / max(1, b.sum()), 100 * MS.ravel()[k].sum() / max(1, MS.sum())))
om = np.argsort(-b)
for f in (0.1, 0.2):
    k = om[:max(1, int(f * len(b)))]
    print("AGREE top %2.0f %% marker bins hold %.1f %% of markers and %.1f %% of overflow" % (100 * f, 100 * b[k].sum() / b.sum(), 100 * a[k].sum() / max(1, a.sum())))
