#!/usr/bin/env python3
"""R12 Q3: per-layer GRT demand (route guides) vs capacity (track grid minus obstructions, x (1 - adj)) per region
of the logic band, + per-layer estimated overflow vs pins per gcell (results/r12.md).
    python3 -I q3.py <r12_obs.txt> <route.guide> <grt.log> <r12_dump.txt> <dumpdb.txt> <ybot> <outdir> [adj 0.25]
Capacity model [E]: an obstruction rect on layer L removes, in every gcell it overlaps, (overlap across the preferred
direction / pitch) tracks weighted by (overlap along the direction / gcell); clipped at the gcell's tracks; x (1 - adj).
Validated against the GRT log's per-layer Resource column (whole die).  Demand: every guide box on L adds 1 per gcell
it covers (vias / pin patches counted like wires, so demand >= GRT usage) - also validated against the log Demand."""
import re, sys
import numpy as np
fo, fg, flog, fd, fdb, ybot, od = sys.argv[1:8]; ybot = float(ybot)
adj = float(sys.argv[8]) if len(sys.argv) > 8 else 0.25
G = 3.0; W, H = 3990.0, None
LY = {}; R = {}
for ln in open(fo):
    t = ln.split()
    if t[0] == "L" and t[1] != "AP": LY[t[1]] = (t[2], float(t[3]))
    elif t[0] == "O" and t[1] in ("M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9"): R.setdefault(t[1], []).append(tuple(map(float, t[2:6])))
rows = [tuple(map(float, l.split()[1:5])) for l in open(fd) if l.startswith("R ")]
H = max(r[3] for r in rows) + 7.2 if False else None
H = float(sys.argv[9]) if len(sys.argv) > 9 else 1751.0
nx, ny = int(W // G), int(H // G)
def ov1(a, b, n):      # per-gcell overlap lengths of [a, b] -> (i0, array)
    i0, i1 = max(0, int(a // G)), min(n - 1, int((b - 1e-9) // G))
    if i1 < i0: return i0, np.zeros(0)
    e = np.arange(i0, i1 + 2) * G
    return i0, np.minimum(e[1:], b) - np.maximum(e[:-1], a)
L2V = {}
for ln in open(flog):
    m = re.search(r"Layer (M\d)\s+Track-Pitch = ([\d.]+)\s+line-2-Via Pitch: ([\d.]+)", ln)
    if m: L2V[m.group(1)] = max(float(m.group(2)), float(m.group(3)))
LY = {L: (d, L2V.get(L, p)) for L, (d, p) in LY.items()}
CAP = {}
for L, (d, p) in LY.items():
    if L == "M1": continue
    tr = G / p; blk = np.zeros((nx, ny))
    for x0, y0, x1, y1 in R.get(L, []):
        ix, fx = ov1(x0, x1, nx); iy, fy = ov1(y0, y1, ny)
        if not len(fx) or not len(fy): continue
        if d == "H": blk[ix:ix + len(fx), iy:iy + len(fy)] += np.outer(fx / G, fy / p)
        else: blk[ix:ix + len(fx), iy:iy + len(fy)] += np.outer(fx / p, fy / G)
    CAP[L] = np.maximum(0.0, tr - blk) * (1 - adj)
DEM = {L: np.zeros((nx, ny)) for L in list(CAP) + ["M1"]}
u = 2000.0
for ln in open(fg):
    t = ln.split()
    if len(t) != 5 or t[4] not in DEM: continue
    x0, y0, x1, y1 = (float(v) / u for v in t[:4])
    i0, i1 = int(x0 // G), min(nx, int(round(x1 / G))); j0, j1 = int(y0 // G), min(ny, int(round(y1 / G)))
    DEM[t[4]][i0:max(i1, i0 + 1), j0:max(j1, j0 + 1)] += 1
LOG = {}
for ln in open(flog):
    m = re.match(r"^(M\d)\s+(\d+)\s+(\d+)\s+([\d.]+)%", ln.strip())
    if m: LOG[m.group(1)] = (int(m.group(2)), int(m.group(3)))
out = ["# R12 Q3 [E] capacity model validation (whole die): layer, model capacity / GRT Resource, guide demand / GRT Demand"]
KC, KD = {}, {}
for L in sorted(CAP):
    r, dm = LOG.get(L, (0, 0)); KC[L] = r / CAP[L].sum(); KD[L] = dm / max(1, DEM[L].sum())
    out.append("VAL %s %s model cap %9.0f GRT res %9d (%.3f) | guide dem %9.0f GRT dem %9d (%.3f)" % (L, LY[L][0], CAP[L].sum(), r, CAP[L].sum() / max(1, r), DEM[L].sum(), dm, DEM[L].sum() / max(1, dm)))
jb = int(np.ceil(ybot / G))
# calibrated: capacity x (GRT resource / model), demand x (GRT demand / guide) per layer (uniform-scaling assumption)
for L in CAP: CAP[L] *= KC[L]; DEM[L] *= KD[L]
out.append("# calibration applied: cap x " + " ".join("%s %.3f" % (L, KC[L]) for L in sorted(KC)) + " ; dem x " + " ".join("%s %.3f" % (L, KD[L]) for L in sorted(KD)))
regs = [("west", 0, 860)] + [("col%d" % c, 860 + 390 * c, 860 + 390 * (c + 1) if c < 7 else W) for c in range(8)]
out.append("# band y >= %.0f: demand / capacity per layer and region (track-gcells, %%); GRT demand scale = guide/GRT ratio not applied" % ybot)
out.append("layer dir " + " ".join("%7s" % r[0] for r in regs) + "   band   dem(M)  cap(M)")
for L in sorted(CAP):
    s = []
    for nm, a, b in regs:
        i0, i1 = int(a // G), int(b // G)
        s.append(100 * DEM[L][i0:i1, jb:].sum() / max(1, CAP[L][i0:i1, jb:].sum()))
    out.append("%-5s %s   " % (L, LY[L][0]) + " ".join("%7.1f" % v for v in s) + "  %5.1f  %6.3f  %6.3f" % (100 * DEM[L][:, jb:].sum() / CAP[L][:, jb:].sum(), DEM[L][:, jb:].sum() / 1e6, CAP[L][:, jb:].sum() / 1e6))
for d in "HV":
    Ls = [L for L in CAP if LY[L][0] == d]
    s = []
    for nm, a, b in regs:
        i0, i1 = int(a // G), int(b // G)
        s.append(100 * sum(DEM[L][i0:i1, jb:].sum() for L in Ls) / sum(CAP[L][i0:i1, jb:].sum() for L in Ls))
    out.append("ALL%s  %s   " % (d, d) + " ".join("%7.1f" % v for v in s) + "  %5.1f   (%s)" % (100 * sum(DEM[L][:, jb:].sum() for L in Ls) / sum(CAP[L][:, jb:].sum() for L in Ls), "+".join(Ls)))
# per-gcell all-layer H: fraction of band gcells where sum demand > sum capacity, and where only some layers exceed
for d in "HV":
    Ls = [L for L in CAP if LY[L][0] == d]
    Dm = sum(DEM[L][:, jb:] for L in Ls); Cp = sum(CAP[L][:, jb:] for L in Ls)
    over = [(DEM[L][:, jb:] > CAP[L][:, jb:]) for L in Ls]
    anyl = np.logical_or.reduce(over); tot = Dm > Cp
    out.append("GCELL %s band gcells %d: some layer over %5.1f %%, all-layer sum over %5.1f %%, layer over but sum fits %5.1f %%"
               % (d, Dm.size, 100 * anyl.mean(), 100 * tot.mean(), 100 * (anyl & ~tot).mean()))
    for L, o in zip(Ls, over): out.append("   %s over in %5.1f %% of band gcells, excess %8.0f track-gcells" % (L, 100 * o.mean(), np.maximum(0, DEM[L][:, jb:] - CAP[L][:, jb:]).sum()))
# pins per gcell (cell centres) vs per-layer excess
A = {}; I = {}; P = {}
for ln in open(fd):
    t = ln.split()
    if t[0] == "M": A[t[1]] = float(t[2])
    elif t[0] == "I": I[t[1]] = (t[2], float(t[3]), float(t[4]))
    elif t[0] == "P": P[t[1]] = (float(t[2]), float(t[3]))
pins = np.zeros((nx, ny))
for ln in open(fdb):
    if not ln.startswith("N "): continue
    for p in ln.split()[2:]:
        if p == "-": continue
        q = P.get(p[5:]) if p.startswith("PORT:") else None
        if not p.startswith("PORT:"):
            i = I.get(p.rsplit(":", 1)[0]); q = (i[1], i[2]) if i and A.get(i[0], 0) <= 1000 else None
        if q: pins[min(nx - 1, int(q[0] // G)), min(ny - 1, int(q[1] // G))] += 1
pb = pins[:, jb:]
out.append("# band gcells by pins per gcell: count | per layer: % of gcells with demand > capacity (M2 M3 M4 M5 M6 M7) | all-layer H over %")
for lo, hi in ((0, 0), (1, 4), (5, 9), (10, 14), (15, 19), (20, 999)):
    m = (pb >= lo) & (pb <= hi)
    s = " ".join("%s %5.1f" % (L, 100 * (DEM[L][:, jb:][m] > CAP[L][:, jb:][m]).mean()) for L in ("M2", "M3", "M4", "M5", "M6", "M7"))
    Ls = [L for L in CAP if LY[L][0] == "H"]
    th = (sum(DEM[L][:, jb:] for L in Ls) > sum(CAP[L][:, jb:] for L in Ls))[m].mean()
    out.append("PINS %3d-%-3d n %7d | %s | allH %5.1f" % (lo, hi, m.sum(), s, 100 * th))
# M1 (resource 0 in GRT) share of the band H overflow: gcells whose H 2D overflow <= their M1 guide count
frpt = sys.argv[10] if len(sys.argv) > 10 else None
if frpt:
    m1 = DEM["M1"]; tot = n1 = 0; left = 0; ov_tr = ov_m1 = 0; cnt = {}
    for ln in open(frpt):
        t = ln.strip()
        if t.startswith("violation type"): d = "H" if "Horizontal" in t else "V"
        elif t.startswith("congestion information"): c, uu, o = map(int, re.search(r"capacity:(\d+) usage:(\d+) overflow:(\d+)", t).groups())
        elif t.startswith("bbox"):
            x1, y1, x2, y2 = map(float, re.search(r"\(\s*([\d.]+),\s*([\d.]+)\s*\)\s*-\s*\(\s*([\d.]+),\s*([\d.]+)\)", t).groups())
            if d != "H" or (y1 + y2) / 2 < ybot: continue
            i, j = int((x1 + x2) / 2 // G), int((y1 + y2) / 2 // G); k = m1[i, j]
            tot += 1; ov_tr += o; ov_m1 += min(o, k); left += (uu - k > c)
            cnt[min(o, 10)] = cnt.get(min(o, 10), 0) + 1
    out.append("# M1 share (guide M1 boxes per gcell, uncalibrated): band H overflowed records %d, overflow %d tracks, of which <= M1 count %d (%.1f %%); records still over without M1 usage %d (%.1f %%)"
               % (tot, ov_tr, ov_m1, 100.0 * ov_m1 / max(1, ov_tr), left, 100.0 * left / max(1, tot)))
    out.append("# band H overflowed records by overflow (tracks): " + " ".join("%s%d:%d" % ("" if k < 10 else ">=", k, v) for k, v in sorted(cnt.items())))
open(od + "/q3_layers.txt", "w").write("\n".join(out) + "\n"); print("\n".join(out))
