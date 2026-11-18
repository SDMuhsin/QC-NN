#!/usr/bin/env python3
"""R21 (results/r21.md): pre-route wire budget of the hub qb_hub - cut demand per cut line, per layer, per net class,
against the capacity at a GRT adjustment (default 0.25 on every layer).  Generalises impl/r18/cuts.py (same guide ->
crossing model and capacity model; R18 hard-coded the act block's die / rows) to any die and cut set; net classes are
impl/r9b/cone.py classes grouped by impl/r10b/ovf10.py grp() (imported, not copied; repair buffers inherit the class
of their source through the comb cone).
    python3 -I cuts21.py <route.guide> <netcls2.txt> <obs.txt> <grt.log> <mplace.tcl> <outdir> [run_adj_spec] [adj 0.25]
run_adj_spec: the GRT adjustment the guides were made with, "M2-M9 0.25" or "M2-M4 0.25 M5-M9 0.10" (layer ranges);
used only to calibrate the model capacity to the GRT log Resource per layer (R18: uniform calibration factor per layer).
Demand: a guide box on a V layer spanning gcell rows j0..j1 crosses the horizontal edges j0+1..j1 in each of its
columns (one track per net per edge); H layers likewise for vertical edges (R18 model, validated vs the GRT Demand).
Cuts: vertical lines (H wiring) at the column boundaries / centres (x0 + 195 k), segmented by the y regions of the
floorplan (south, S0, ch01, S1, band, S2, ch23, S3, north); horizontal lines (V wiring) every 30 um, segmented by the
x regions (west strip, col0..col7).  Output: per segment and layer demand / capacity, class shares, and a ranked list of
over-budget items (> QB21_OVB [0.75] of capacity) with the class mix."""
import ast, os, re, sys, collections as C
import numpy as np
fg, fn, fo, flog, fmp, od = sys.argv[1:7]
RUNADJ = sys.argv[7] if len(sys.argv) > 7 else "M2-M9 0.25"
ADJ = float(sys.argv[8]) if len(sys.argv) > 8 else 0.25
OVB = float(os.environ.get("QB21_OVB", "0.75"))
G, U = 3.0, 2000.0
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "..", "r10b", "ovf10.py")).read()
fnd = [n for n in ast.parse(src).body if isinstance(n, ast.FunctionDef) and n.name == "grp"][0]
ns = {}; exec(compile(ast.Module(body=[fnd], type_ignores=[]), "ovf10.py", "exec"), ns); grp = ns["grp"]
LAYERS = ["M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9"]
def lnum(L): return int(L[1:])
def adjspec(s):
    a = {}; t = s.split()
    for k in range(0, len(t), 2):
        lo, hi = (t[k].split("-") + [t[k]])[:2]
        for n in range(lnum(lo), lnum(hi) + 1): a["M%d" % n] = float(t[k + 1])
    return a
RA = adjspec(RUNADJ)
# ---- floorplan
mp = open(fmp).read()
W = float(re.search(r"DIE_AREA\)\s*\{0 0 ([\d.]+) ([\d.]+)\}", mp).group(1)); H = float(re.search(r"DIE_AREA\)\s*\{0 0 ([\d.]+) ([\d.]+)\}", mp).group(2))
X0 = float(os.environ.get("QB21_X0", "860")); CW = 390.0
# S macro row bottoms (MPLACE15 log line of the run; default = QB15_FP mid)
srow = [float(v) for v in os.environ.get("QB21_SROWS", "361.4 606.2 1297.4 1540.4").split()]
SH = float(os.environ.get("QB21_SH", "204.1"))
nx, ny = int(np.ceil(W / G)), int(np.ceil(H / G))
# ---- classes
NC = {}
for ln in open(fn):
    f = ln.split()
    if len(f) >= 2: NC[f[0]] = grp(f[1])
CLS = sorted(set(NC.values())) + ["unclassified"]; CI = {c: i for i, c in enumerate(CLS)}
# ---- layers / obstructions (impl/r12/q3dump.tcl)
LY = {}; OB = C.defaultdict(list)
for ln in open(fo):
    t = ln.split()
    if t[0] == "L" and t[1] in LAYERS: LY[t[1]] = (t[2], float(t[3]))
    elif t[0] == "O" and t[1] in LAYERS: OB[t[1]].append(tuple(map(float, t[2:6])))
RES, DEM = {}, {}
for ln in open(flog):
    m = re.match(r"^(M\d)\s+(\d+)\s+(\d+)\s+([\d.]+)%\s+(\d+)\s*/\s*(\d+)\s*/\s*(\d+)", ln.strip())
    if m: RES[m.group(1)] = int(m.group(2)); DEM[m.group(1)] = int(m.group(3))
def ov1(a, b, n):
    i0, i1 = max(0, int(a // G)), min(n - 1, int((b - 1e-9) // G))
    if i1 < i0: return i0, np.zeros(0)
    e = np.arange(i0, i1 + 2) * G
    return i0, np.minimum(e[1:], b) - np.maximum(e[:-1], a)
CAP, KC = {}, {}
for L, (d, p) in LY.items():
    blk = np.zeros((nx, ny), np.float32)
    for x0, y0, x1, y1 in OB[L]:
        ix, fx = ov1(x0, x1, nx); iy, fy = ov1(y0, y1, ny)
        if not len(fx) or not len(fy): continue
        if d == "H": blk[ix:ix + len(fx), iy:iy + len(fy)] += np.outer(fx / G, fy / p)
        else: blk[ix:ix + len(fx), iy:iy + len(fy)] += np.outer(fx / p, fy / G)
    raw = np.maximum(0.0, G / p - blk)
    KC[L] = RES.get(L, 0) / max(1e-9, raw.sum() * (1 - RA.get(L, 0.25)))     # calibration at the run's adjustment
    CAP[L] = (raw * (1 - ADJ) * KC[L]).astype(np.float32)                      # capacity at the budget adjustment
VL = [L for L in LAYERS if L in LY and LY[L][0] == "V"]; HL = [L for L in LAYERS if L in LY and LY[L][0] == "H"]
# ---- guides -> crossings XV[c, l, i, e] (edge e between rows e-1 / e), XH[c, l, e, j]
XV = np.zeros((len(CLS), len(VL), nx, ny + 1), np.int32); XH = np.zeros((len(CLS), len(HL), nx + 1, ny), np.int32)
seg = C.defaultdict(list); net = None
for ln in open(fg):
    t = ln.split()
    if len(t) == 1 and t[0] not in "()": net = t[0]; continue
    if len(t) != 5 or t[4] not in LY: continue
    x0, y0, x1, y1 = (int(round(int(v) / U / G)) for v in t[:4])
    c = CI[NC.get(net, "unclassified")]
    if LY[t[4]][0] == "V" and y1 - y0 > 1: seg[("V", t[4])].append((c, x0, x1, y0, y1))
    elif LY[t[4]][0] == "H" and x1 - x0 > 1: seg[("H", t[4])].append((c, x0, x1, y0, y1))
for (d, L), s in seg.items():
    a = np.array(s, np.int64)
    if d == "V":
        li = VL.index(L); D = np.zeros((len(CLS), nx, ny + 2), np.int32)
        for w in np.unique(a[:, 2] - a[:, 1]):
            b = a[a[:, 2] - a[:, 1] == w]
            for k in range(w):
                np.add.at(D, (b[:, 0], np.minimum(b[:, 1] + k, nx - 1), b[:, 3] + 1), 1)
                np.add.at(D, (b[:, 0], np.minimum(b[:, 1] + k, nx - 1), np.minimum(b[:, 4], ny + 1)), -1)
        XV[:, li] = np.cumsum(D, axis=2)[:, :, :ny + 1]
    else:
        li = HL.index(L); D = np.zeros((len(CLS), nx + 2, ny), np.int32)
        for w in np.unique(a[:, 4] - a[:, 3]):
            b = a[a[:, 4] - a[:, 3] == w]
            for k in range(w):
                np.add.at(D, (b[:, 0], b[:, 1] + 1, np.minimum(b[:, 3] + k, ny - 1)), 1)
                np.add.at(D, (b[:, 0], np.minimum(b[:, 2], nx + 1), np.minimum(b[:, 3] + k, ny - 1)), -1)
        XH[:, li] = np.cumsum(D, axis=1)[:, :nx + 1, :]
del seg
out = ["# R21 cuts21.py: budget adjustment %.2f (run %s), gcell %.1f um, grid %d x %d, die %.1f x %.1f, classes %d (nets %d), over-budget > %.0f %%"
       % (ADJ, RUNADJ, G, nx, ny, W, H, len(CLS), len(NC), 100 * OVB)]
for L in LAYERS:
    if L not in LY: continue
    X = XV[:, VL.index(L)].sum() if L in VL else XH[:, HL.index(L)].sum()
    cp = CAP[L].sum()
    out.append("VAL %s %s crossings %9d GRT demand %9d (%.3f) | GRT resource %9d cal x %.3f | cap@%.2f %9.0f | whole-die use %5.1f %%"
               % (L, LY[L][0], X, DEM.get(L, 0), X / max(1, DEM.get(L, 0)), RES.get(L, 0), KC[L], ADJ, cp, 100.0 * X / max(cp, 1)))
# edge capacity = min of the two gcells
def ecap(L):
    c = CAP[L]
    if L in VL: e = np.zeros((nx, ny + 1), np.float32); e[:, 1:ny] = np.minimum(c[:, :-1], c[:, 1:])
    else: e = np.zeros((nx + 1, ny), np.float32); e[1:nx, :] = np.minimum(c[:-1, :], c[1:, :])
    return e
EC = {L: ecap(L) for L in VL + HL}
# regions
ylo = min(srow) if srow else 361.0
YR = [("south", 0.0, srow[0])] if srow else []
for k, y in enumerate(srow):
    YR.append(("S%d" % k, y, y + SH))
    if k + 1 < len(srow):
        nm = "band" if srow[k + 1] - (y + SH) > 100 else "ch%d%d" % (k, k + 1)
        YR.append((nm, y + SH, srow[k + 1]))
if srow: YR.append(("north", srow[-1] + SH, H))
XR = [("west", 0.0, X0)] + [("col%d" % c, X0 + CW * c, min(W, X0 + CW * (c + 1))) for c in range(8)]
rows = []          # (ratio, kind, pos, region, layer, dem, cap, class shares)
def addrow(kind, pos, reg, L, dvec, cap):
    tot = dvec.sum()
    sh = sorted(((dvec[k], CLS[k]) for k in range(len(CLS)) if dvec[k] > 0), reverse=True)
    rows.append((tot / max(cap, 1.0), kind, pos, reg, L, int(tot), cap, sh))
# vertical cuts (H wiring): x edges at X0 + 195 k (and the west strip mid)
xcuts = [430.0] + [X0 + 195.0 * k for k in range(0, 16)] + [min(W - 3, X0 + 195.0 * 16)]
for x in xcuts:
    e = int(round(x / G))
    for nm, a, b in YR:
        j0, j1 = int(a // G), int(min(ny, np.ceil(b / G)))
        for L in HL:
            li = HL.index(L)
            addrow("x", x, nm, L, XH[:, li, e, j0:j1].sum(axis=1), float(EC[L][e, j0:j1].sum()))
        addrow("x", x, nm, "allH", sum(XH[:, HL.index(L), e, j0:j1].sum(axis=1) for L in HL), float(sum(EC[L][e, j0:j1].sum() for L in HL)))
# horizontal cuts (V wiring) every 30 um
for y in np.arange(30.0, H, 30.0):
    e = int(round(y / G))
    for nm, a, b in XR:
        i0, i1 = int(a // G), int(min(nx, np.ceil(b / G)))
        for L in VL:
            li = VL.index(L)
            addrow("y", y, nm, L, XV[:, li, i0:i1, e].sum(axis=1), float(EC[L][i0:i1, e].sum()))
        addrow("y", y, nm, "allV", sum(XV[:, VL.index(L), i0:i1, e].sum(axis=1) for L in VL), float(sum(EC[L][i0:i1, e].sum() for L in VL)))
def fmt(r):
    q, kind, pos, reg, L, tot, cap, sh = r
    return "%s %7.1f %-6s %-4s %7d / %8.0f = %5.1f %% | " % (kind, pos, reg, L, tot, cap, 100 * q) + \
        "  ".join("%s %.0f%%" % (c.replace(" ", "_"), 100.0 * v / max(tot, 1)) for v, c in sh[:5])
out.append("# over-budget items (demand > %.0f %% of capacity at adj %.2f), worst first: kind pos region layer dem / cap = ratio | top classes" % (100 * OVB, ADJ))
ovb = sorted((r for r in rows if r[0] > OVB and r[6] > 50), key=lambda r: -r[0])
for r in ovb[:80]: out.append("OVB " + fmt(r))
out.append("# over-budget count by (kind, region, layer)")
cnt = C.Counter((r[1], r[3], r[4]) for r in ovb)
for k, v in cnt.most_common(40): out.append("OVBN %s %-6s %-4s %d" % (k[0], k[1], k[2], v))
# class share of the demand over all over-budget items (layer-summed rows excluded)
cs = C.Counter(); tt = 0
for r in ovb:
    if r[4] in ("allH", "allV"): continue
    for v, c in r[7]: cs[c] += v
    tt += r[5]
out.append("# class share of the demand on over-budget (cut segment, layer) items: %d items, %d track crossings" % (sum(1 for r in ovb if r[4] not in ("allH", "allV")), tt))
for c, v in cs.most_common(20): out.append("OVBCLS %-26s %5.1f %%" % (c, 100.0 * v / max(tt, 1)))
# per region worst cut (layer-summed)
out.append("# worst layer-summed cut per region: H wiring (vertical cuts) and V wiring (horizontal cuts)")
for kind, LL, RR in (("x", "allH", YR), ("y", "allV", XR)):
    for nm, a, b in RR:
        rr = [r for r in rows if r[1] == kind and r[3] == nm and r[4] == LL]
        if rr: out.append("WORST " + fmt(max(rr, key=lambda r: r[0])))
# whole-die demand by class and direction
out.append("# whole-die crossings by class: V (share) H (share)")
TV = XV.sum(axis=(1, 2, 3)); TH = XH.sum(axis=(1, 2, 3))
for k in np.argsort(-(TV + TH)):
    out.append("TOT %-26s V %9d %5.1f %%  H %9d %5.1f %%" % (CLS[k], TV[k], 100.0 * TV[k] / TV.sum(), TH[k], 100.0 * TH[k] / TH.sum()))
os.makedirs(od, exist_ok=True)
with open(os.path.join(od, "cuts21_adj%.2f.txt" % ADJ), "w") as f: f.write("\n".join(out) + "\n")
with open(os.path.join(od, "cuts21_rows_adj%.2f.txt" % ADJ), "w") as f:
    for r in sorted(rows, key=lambda r: -r[0]): f.write(fmt(r) + "\n")
print("\n".join(out))
