#!/usr/bin/env python3
"""R18 (results/r18.md): cut-demand decomposition of qb_act2_blk by net class, from GRT guides.
    python3 -I cuts.py <route.guide> <nets.txt> <cells.txt> <obs.txt> <grt.log> <adj> <outdir> [step_um 30]
Demand: a guide box on a V layer (M2/M4/M6) spanning gcell rows j0..j1 crosses the horizontal gcell edges j0+1..j1 in each of
its columns (1 track per net per edge); H layers (M3/M5/M7) likewise for vertical edges.  Pin / via patches (1 gcell) cross
nothing.  Validated per layer against the GRT log Demand.
Capacity per gcell edge [E]: tracks per gcell (G / pitch) minus PDN / obstruction tracks (impl/r12/q3dump.tcl rects, same
model as impl/r12/q3.py), x (1 - adj), then scaled per layer to the GRT log Resource (uniform calibration).
Cuts: horizontal cuts at the midpoints between consecutive act-row y centroids (act regs, row = i / 288), and every <step>
um in y and x.  Per cut: crossings by class (all layers of the crossing direction), cut capacity, local overflow =
sum over the cut's gcell edges of max(0, D - C) (layer-summed, 2-D view), and the overflow left if a class vanished."""
import re, sys, collections as C
import numpy as np
fg, fn, fc, fo, flog, adj, od = sys.argv[1:8]; adj = float(adj)
STEP = float(sys.argv[8]) if len(sys.argv) > 8 else 30.0
G, U = 3.0, 2000.0
# ---- classes
sys.path.insert(0, __import__("os").path.dirname(__file__))
import cls18
NC = cls18.load(fn)
with open(od + "/netcls18.txt", "w") as f:
    for n, c in NC.items(): f.write("%s %s\n" % (n, c.replace(" ", "_")))
CLS = sorted(set(NC.values())) + ["unclassified"]
CI = {c: i for i, c in enumerate(CLS)}
# ---- die / layers
W, H = 900.0, 1970.0
nx, ny = int(np.ceil(W / G)), int(np.ceil(H / G))
LY = {}; OB = C.defaultdict(list)
for ln in open(fo):
    t = ln.split()
    if t[0] == "L" and t[1] in ("M2", "M3", "M4", "M5", "M6", "M7"): LY[t[1]] = (t[2], float(t[3]))
    elif t[0] == "O" and t[1] in ("M2", "M3", "M4", "M5", "M6", "M7"): OB[t[1]].append(tuple(map(float, t[2:6])))
RES, DEM = {}, {}
for ln in open(flog):
    m = re.match(r"^(M\d)\s+(\d+)\s+(\d+)\s+([\d.]+)%\s+(\d+)\s*/\s*(\d+)\s*/\s*(\d+)", ln.strip())
    if m: RES[m.group(1)] = int(m.group(2)); DEM[m.group(1)] = int(m.group(3))
def ov1(a, b, n):
    i0, i1 = max(0, int(a // G)), min(n - 1, int((b - 1e-9) // G))
    if i1 < i0: return i0, np.zeros(0)
    e = np.arange(i0, i1 + 2) * G
    return i0, np.minimum(e[1:], b) - np.maximum(e[:-1], a)
CAP = {}
for L, (d, p) in LY.items():
    blk = np.zeros((nx, ny))
    for x0, y0, x1, y1 in OB[L]:
        ix, fx = ov1(x0, x1, nx); iy, fy = ov1(y0, y1, ny)
        if not len(fx) or not len(fy): continue
        if d == "H": blk[ix:ix + len(fx), iy:iy + len(fy)] += np.outer(fx / G, fy / p)
        else: blk[ix:ix + len(fx), iy:iy + len(fy)] += np.outer(fx / p, fy / G)
    CAP[L] = np.maximum(0.0, G / p - blk) * (1 - adj)
KC = {L: RES.get(L, 0) / CAP[L].sum() for L in CAP}
for L in CAP: CAP[L] *= KC[L]
VL = [L for L in sorted(LY) if LY[L][0] == "V"]; HL = [L for L in sorted(LY) if LY[L][0] == "H"]
# ---- guides -> crossings: XV[c, l, i, e] (edge e between rows e-1 / e), XH[c, l, e, j]
XV = np.zeros((len(CLS), len(VL), nx, ny + 1), np.int32); XH = np.zeros((len(CLS), len(HL), nx + 1, ny), np.int32)
seg = C.defaultdict(list)
net = None
for ln in open(fg):
    t = ln.split()
    if len(t) == 1 and t[0] not in "()": net = t[0]; continue
    if len(t) != 5 or t[4] not in LY: continue
    x0, y0, x1, y1 = (int(round(int(v) / U / G)) for v in t[:4])
    if LY[t[4]][0] == "V" and y1 - y0 > 1: seg[("V", t[4])].append((CI[NC.get(net, "unclassified")], x0, x1, y0, y1))
    elif LY[t[4]][0] == "H" and x1 - x0 > 1: seg[("H", t[4])].append((CI[NC.get(net, "unclassified")], x0, x1, y0, y1))
for (d, L), s in seg.items():
    a = np.array(s, np.int64)
    if d == "V":
        li = VL.index(L); D = np.zeros((len(CLS), nx, ny + 2), np.int32)
        for w in np.unique(a[:, 2] - a[:, 1]):
            b = a[a[:, 2] - a[:, 1] == w]
            for k in range(w):
                np.add.at(D, (b[:, 0], np.minimum(b[:, 1] + k, nx - 1), b[:, 3] + 1), 1)
                np.add.at(D, (b[:, 0], np.minimum(b[:, 1] + k, nx - 1), b[:, 4]), -1)
        XV[:, li] = np.cumsum(D, axis=2)[:, :, :ny + 1]
    else:
        li = HL.index(L); D = np.zeros((len(CLS), nx + 2, ny), np.int32)
        for w in np.unique(a[:, 4] - a[:, 3]):
            b = a[a[:, 4] - a[:, 3] == w]
            for k in range(w):
                np.add.at(D, (b[:, 0], b[:, 1] + 1, np.minimum(b[:, 3] + k, ny - 1)), 1)
                np.add.at(D, (b[:, 0], b[:, 2], np.minimum(b[:, 3] + k, ny - 1)), -1)
        XH[:, li] = np.cumsum(D, axis=1)[:, :nx + 1, :]
out = ["# R18 cuts.py adj %.2f  gcell %.1f um  grid %d x %d  classes %d (nets classified %d)" % (adj, G, nx, ny, len(CLS), len(NC))]
out.append("# per layer: guide crossings vs GRT log Demand, model capacity calibration (cap x)")
for L in sorted(LY):
    X = XV[:, VL.index(L)].sum() if L in VL else XH[:, HL.index(L)].sum()
    out.append("VAL %s %s crossings %9d GRT demand %9d (%.3f) | GRT resource %9d cap x %.3f" % (L, LY[L][0], X, DEM.get(L, 0), X / max(1, DEM.get(L, 0)), RES.get(L, 0), KC[L]))
# edge capacities: V edge (i, e) between gcells (i, e-1) and (i, e) -> min of the two; H edge (e, j) likewise
def vcap(L):
    c = CAP[L]; e = np.zeros((nx, ny + 1)); e[:, 1:ny] = np.minimum(c[:, :-1], c[:, 1:]); return e
def hcap(L):
    c = CAP[L]; e = np.zeros((nx + 1, ny)); e[1:nx, :] = np.minimum(c[:-1, :], c[1:, :]); return e
CV = sum(vcap(L) for L in VL); CH = sum(hcap(L) for L in HL)
DV = XV.sum(axis=1); DH = XH.sum(axis=1)          # [c, i, e] / [c, e, j]
TV = DV.sum(axis=0); TH = DH.sum(axis=0)
out.append("# whole block, crossings by class (track-edges): class  V  (share)  H  (share)")
for c in CLS:
    v, h = DV[CI[c]].sum(), DH[CI[c]].sum()
    out.append("TOT %-18s V %9d %5.1f %%  H %9d %5.1f %%" % (c, v, 100.0 * v / TV.sum(), h, 100.0 * h / TH.sum()))
out.append("TOT %-18s V %9d (cap %9.0f, %5.1f %%)  H %9d (cap %9.0f, %5.1f %%)" % ("all", TV.sum(), CV.sum(), 100 * TV.sum() / CV.sum(), TH.sum(), CH.sum(), 100 * TH.sum() / CH.sum()))
ovV = np.maximum(0, TV - CV); ovH = np.maximum(0, TH - CH)
out.append("# 2-D edge overflow (layer-summed, model capacity): V %.0f tracks on %d edges, H %.0f on %d edges" % (ovV.sum(), (ovV > 0).sum(), ovH.sum(), (ovH > 0).sum()))
def cutline(name, D, T, Cp, idx, axis):
    # D [c, i, e] for V (axis 'y': fix e) / [c, e, j] for H (fix e)
    if axis == "y": d = D[:, :, idx]; t = T[:, idx]; cp = Cp[:, idx]
    else: d = D[:, idx, :]; t = T[idx, :]; cp = Cp[idx, :]
    tot, cap = t.sum(), cp.sum(); ov = np.maximum(0, t - cp).sum()
    sh = sorted(((d[k].sum(), CLS[k]) for k in range(len(CLS))), reverse=True)
    left = {CLS[k]: np.maximum(0, t - d[k] - cp).sum() for k in range(len(CLS))}
    return tot, cap, ov, sh, left
def report(title, D, T, Cp, idxs, axis, pos):
    rows = []
    for e in idxs:
        tot, cap, ov, sh, left = cutline(title, D, T, Cp, e, axis)
        rows.append((tot / max(cap, 1), e, tot, cap, ov, sh, left))
    out.append("# %s: cut  pos(um)  crossings / capacity (%%)  local overflow  | top classes share (overflow left if the class vanished)" % title)
    for r, e, tot, cap, ov, sh, left in rows:
        out.append("CUT %s %7.1f  %7d / %7.0f (%5.1f %%)  ov %6.0f | " % (axis, pos(e), tot, cap, 100 * r, ov) +
                   "  ".join("%s %.1f%% (%.0f)" % (c.replace(" ", "_"), 100.0 * v / max(tot, 1), left[c]) for v, c in sh[:7]))
    return rows
# act rows
rowy = C.defaultdict(list)
for ln in open(fc):
    t = ln.split()
    if t[0] == "s2ff" and t[5] != "-": rowy[int(t[5])].append(float(t[2]))
cy = sorted((np.mean(v), r) for r, v in rowy.items())
out.append("# act rows (act reg y centroid um, row): " + " ".join("r%d %.0f" % (r, y) for y, r in cy))
cuts = [int(round((cy[k][0] + cy[k + 1][0]) / 2 / G)) for k in range(len(cy) - 1)]
report("horizontal cuts between act rows (V wiring)", DV, TV, CV, cuts, "y", lambda e: e * G)
ys = [int(round(y / G)) for y in np.arange(STEP, H, STEP)]
rows = report("horizontal cuts every %.0f um (V wiring)" % STEP, DV, TV, CV, ys, "y", lambda e: e * G)
xs = [int(round(x / G)) for x in np.arange(STEP, W, STEP)]
rowsx = report("vertical cuts every %.0f um (H wiring)" % STEP, DH, TH, CH, xs, "x", lambda e: e * G)
for nm, rr in (("y (V wiring)", rows), ("x (H wiring)", rowsx)):
    w = sorted(rr, key=lambda r: -r[4])[:5]
    out.append("# worst 5 %s cuts by local overflow: what-if per class, overflow left (%% of the cut's overflow)" % nm)
    for r, e, tot, cap, ov, sh, left in w:
        out.append("WORST %s %7.1f ov %6.0f util %5.1f %% | " % (nm[0], e * G, ov, 100 * r) + "  ".join("%s %.0f%%" % (c.replace(" ", "_"), 100.0 * left[c] / max(ov, 1)) for v, c in sh[:8]))
# per-class whole-block what-if on the 2-D edge overflow
out.append("# whole-block 2-D edge overflow left if a class vanished: class  V left (%)  H left (%)")
for c in CLS:
    k = CI[c]
    lv = np.maximum(0, TV - DV[k] - CV).sum(); lh = np.maximum(0, TH - DH[k] - CH).sum()
    out.append("WHATIF %-18s V %8.0f (%5.1f %%)  H %8.0f (%5.1f %%)" % (c, lv, 100 * lv / max(1, ovV.sum()), lh, 100 * lh / max(1, ovH.sum())))
fam = {"S1 family (lbm + S1 internal)": ("lbm S1-term-in", "S1 int tree", "S1 int->reg"), "lb family (lbf, shift, write, D-logic)": ("lbf pre-mux-in", "lb slot-shift", "lbf+shift", "lb write rdq/sdq", "lb wsrc s_q/m_q", "lb D-local", "lb D-fan(wd)", "lb other"),
       "select broadcasts": tuple(c for c in CLS if c.startswith("sel "))}
fam["lb write path (rdq/sdq + wd fan)"] = ("lb write rdq/sdq", "lb D-fan(wd)")
fam["S1 internal (tree + ->reg)"] = ("S1 int tree", "S1 int->reg")
for nm, ks in fam.items():
    lv = np.maximum(0, TV - sum(DV[CI[k]] for k in ks if k in CI) - CV).sum(); lh = np.maximum(0, TH - sum(DH[CI[k]] for k in ks if k in CI) - CH).sum()
    out.append("WHATIF-FAM %-40s V %8.0f (%5.1f %%)  H %8.0f (%5.1f %%)" % (nm, lv, 100 * lv / max(1, ovV.sum()), lh, 100 * lh / max(1, ovH.sum())))
# 2-D overflow maps (100-um bins) for ovfmap.py
B = 100.0
mv = np.zeros((int(np.ceil(W / B)), int(np.ceil(H / B)))); mh = np.zeros_like(mv)
ii, ee = np.nonzero(ovV)
np.add.at(mv, ((ii * G // B).astype(int), np.minimum(mv.shape[1] - 1, (ee * G // B).astype(int))), ovV[ii, ee])
ee, jj = np.nonzero(ovH)
np.add.at(mh, (np.minimum(mh.shape[0] - 1, (ee * G // B).astype(int)), (jj * G // B).astype(int)), ovH[ee, jj])
np.save(od + "/edgeovf_adj%.2f.npy" % adj, np.stack([mv, mh]))
# per-class crossings per y band (100 um) for the placement report
out.append("# V crossings of horizontal edges per 100-um y band (k tracks) by class")
yb = (np.arange(ny + 1) * G // B).astype(int)
hdr = [c for c in CLS if DV[CI[c]].sum() > 0.01 * TV.sum()]
out.append("YB  y0  " + " ".join("%10s" % c[:10].replace(" ", "_") for c in hdr) + "   total  cap")
for b in range(yb.max() + 1):
    m = yb == b
    out.append("YB %4.0f " % (b * B) + " ".join("%10.1f" % (DV[CI[c]][:, m].sum() / 1e3) for c in hdr) + "  %7.1f %6.1f" % (TV[:, m].sum() / 1e3, CV[:, m].sum() / 1e3))
open(od + "/cuts_adj%.2f.txt" % adj, "w").write("\n".join(out) + "\n")
print("\n".join(out))
