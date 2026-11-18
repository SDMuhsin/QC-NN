#!/usr/bin/env python3
"""R23 (results/r23.md): column-order feasibility estimate for the south hub (no P&R).
    python3 -I aff23.py <aff23 dump> <netcls2.txt> <outdir> [orders, comma-separated, default 01234567,04152637,40516273]
Input: impl/r23/aff23.tcl dump of a placed hub (pn2: db/place.odb), the run's GRT netcls2 classes (impl/r10b ovf10 grp).
Model (all x only; y of every object is kept):
  anchors  S macro lane L -> logical column L % 8; hub ports at x >= X0 -> column floor((x - X0) / 390) (column south /
           north pins); B / P macros -> column by connectivity affinity (QB23_BP perm: move with that column; fixed: stay);
           west-strip ports / FC / IMG / params 8 stay.  A permuted order puts logical column order[i] in slot i; an
           anchor of column c moves by the x offset between the same object type at slot pos(c) and at slot c.
  A        every std cell moves with the slot it sits under in the placement (no re-placement).
  N        as R from a neutral start (all free cells at one x, QB23_IT0 [30] unlegalised steps): no identity bias
  R        std cells re-placed: Jacobi clique-model relaxation from A (QB23_IT [40] iterations, nets <= 64 pins), with a
           rank-preserving x legalisation after each one (the x density profile of the placement is kept).  The same R
           on the identity order is the reference (validates R against the measured placement A0).
Crossings: H wiring = nets whose x span crosses the column boundary x = X0 + 390 k (k 0..7; k 0 = west boundary),
  total and band-weighted (fraction of the net's y span inside the logic band); V proxy = nets whose y span crosses a
  horizontal line, spread over their x span (uniform L-route), summed per column slot.  Per cut the class shares."""
import ast, os, re, sys, collections as C
import numpy as np
import scipy.sparse as sp
fd, fn, od = sys.argv[1:4]
ORD = (sys.argv[4] if len(sys.argv) > 4 else "01234567,04152637,40516273").split(",")
X0, CW, NCOL = 860.0, 390.0, 8
BAND = tuple(map(float, os.environ.get("QB23_BAND", "848 1485").split()))
YV = [float(v) for v in os.environ.get("QB23_YV", "1504.6 1166 664").split()]   # S3 pin edge, band mid, S2 pin edge
IT, MAXD = int(os.environ.get("QB23_IT", "40")), int(os.environ.get("QB23_MAXD", "64"))
os.makedirs(od, exist_ok=True)
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "..", "r10b", "ovf10.py")).read()
fnd = [n for n in ast.parse(src).body if isinstance(n, ast.FunctionDef) and n.name == "grp"][0]
ns = {}; exec(compile(ast.Module(body=[fnd], type_ignores=[]), "ovf10.py", "exec"), ns); grp = ns["grp"]
# ---- dump
mst, X, Y, mac = [], [], [], {}
nets, nname = [], []
for ln in open(fd):
    t = ln.split()
    if t[0] == "I":
        mst.append(t[2]); X.append(float(t[3])); Y.append(float(t[4]))
        if t[5] == "1": mac[int(t[1])] = t[6]
    elif t[0] == "N":
        nname.append(t[1].replace("\\", "")); nets.append(t[2:])
X, Y = np.array(X), np.array(Y); NI = len(X)
# ports become extra objects (anchors)
px, py, pnets = [], [], []
for k, toks in enumerate(nets):
    out = []
    for tk in toks:
        if tk[0] == "p":
            a, b = tk[1:].split(":"); out.append(NI + len(px)); px.append(float(a)); py.append(float(b))
        else: out.append(int(tk))
    nets[k] = out
XA, YA = np.concatenate([X, px]), np.concatenate([Y, py]); NO = len(XA)
ismac = np.zeros(NO, bool); ismac[list(mac)] = True
isport = np.zeros(NO, bool); isport[NI:] = True
cls = {}
for ln in open(fn):
    f = ln.split()
    if len(f) >= 2: cls[f[0].replace("\\", "")] = grp(f[1])
ncls = [cls.get(n, "unclassified") for n in nname]
slot_of = lambda x: np.where(x < X0, -1, np.minimum(((x - X0) // CW).astype(int), NCOL - 1))
# ---- anchor columns
col = np.full(NO, -9)                                      # -9 free std cell, -1 fixed (west / not column), 0..7
kind = {}
for i, n in mac.items():
    m = re.search(r"g_s_(\d+)__u_m", n)
    if m: col[i] = int(m.group(1)) % 8; kind[i] = "S"; continue
    m = re.search(r"g_map_(\d+)__g_mm_(\d+)_", n)
    if m: kind[i] = "B%d" % (4 * int(m.group(1)) + int(m.group(2))); col[i] = -1; continue
    m = re.search(r"g_pm_(\d+)_", n)
    if m: kind[i] = "P%d" % int(m.group(1)); col[i] = -1; continue
    col[i] = -1; kind[i] = "M"
col[NI:] = slot_of(XA[NI:])
# ---- B / P affinity: column ports reached from the macro's pins within QB23_AFD [3] nets (std cells passed through)
o2n = C.defaultdict(list)
for k, ob in enumerate(nets):
    if len(ob) <= MAXD:
        for o in ob: o2n[o].append(k)
AFD = int(os.environ.get("QB23_AFD", "3"))
aff = {}
for i in sorted(mac):
    if kind[i][0] not in "BP": continue
    seen, front, cnt = {i}, [i], np.zeros(NCOL)
    for _ in range(AFD):
        nxt = []
        for o in front:
            for k in o2n[o]:
                for q in nets[k]:
                    if q in seen: continue
                    seen.add(q)
                    if isport[q] and col[q] >= 0: cnt[col[q]] += 1
                    elif not ismac[q] and not isport[q]: nxt.append(q)
        front = nxt
    aff[i] = cnt
rep = open(os.path.join(od, "aff23_affinity.txt"), "w")
for i in sorted(aff, key=lambda i: kind[i]):
    c = aff[i]; s = c.sum()
    best = int(np.argmax(c)) if s else -1
    rep.write("%s x %.0f -> col ports reached %s ; best col %d (%.0f %%)\n" % (kind[i], XA[i], " ".join("%d" % v for v in c), best, 100 * c[best] / s if s else 0))
    if os.environ.get("QB23_BP", "perm") == "perm" and s and c[best] / s >= 0.5 and kind[i] != "P8":
        col[i] = best
rep.close()
def place(order, mode):
    pos = {int(ch): s for s, ch in enumerate(order)}        # logical column -> physical slot
    inv = {s: c for c, s in pos.items()}                    # physical slot -> logical column (identity layout)
    x = XA.copy()
    ref = C.defaultdict(dict)
    for i in mac:
        if col[i] >= 0: ref[(kind[i][0], int(round(YA[i])))][col[i]] = XA[i]
    for i in mac:
        if col[i] >= 0:
            r = ref[(kind[i][0], int(round(YA[i])))]
            tgt = pos[col[i]]                                # slot this column goes to; identity object there = inv[tgt]
            x[i] = r[tgt] if tgt in r else XA[i] + CW * (tgt - col[i])
    pm = isport & (col >= 0)
    x[pm] = XA[pm] + CW * (np.array([pos[c] for c in col[pm]]) - col[pm])
    free = ~ismac & ~isport
    sl = slot_of(XA)
    fm = free & (sl >= 0)
    x[fm] = XA[fm] + CW * (np.array([pos[c] for c in sl[fm]]) - sl[fm])
    if mode == "A": return x
    # R: relaxation of the free cells
    fidx = np.where(free)[0]; fpos = -np.ones(NO, int); fpos[fidx] = np.arange(len(fidx))
    rows, cols_, w, anc = [], [], [], []
    keep = [k for k, ob in enumerate(nets) if 2 <= len(ob) <= MAXD]
    for k in keep:
        ob = nets[k]
        for o in ob: rows.append(len(anc)); cols_.append(o); w.append(1.0)
        anc.append(1.0 / (len(ob) - 1))
    Inc = sp.csr_matrix((w, (rows, cols_)), shape=(len(keep), NO))
    wn = np.array(anc); deg = np.asarray(Inc.sum(1)).ravel()
    IncT = Inc.T.tocsr()
    target_sorted = np.sort(x[fidx])                        # legalisation profile (density in x kept)
    if mode == "N":                                         # neutral start: every free cell at the mean x, then
        x[fidx] = target_sorted.mean()                      # QB23_IT0 unlegalised Jacobi steps (anchors propagate)
        for _ in range(int(os.environ.get("QB23_IT0", "30"))):
            s = Inc @ x
            num = IncT @ (wn * s) - x * (IncT @ wn); den = IncT @ (wn * (deg - 1))
            x[fidx] = np.where(den > 0, num / np.maximum(den, 1e-12), x)[fidx]
    for _ in range(IT):
        s = Inc @ x
        num = IncT @ (wn * s) - x * (IncT @ wn)             # sum_n w_n (s_n - x_i)
        den = IncT @ (wn * (deg - 1))
        nx = np.where(den > 0, num / np.maximum(den, 1e-12), x)
        xf = nx[fidx]
        x[fidx[np.argsort(xf, kind="mergesort")]] = target_sorted
    return x
def cuts(x, tag, out):
    lo = np.array([min(x[o] for o in ob) for ob in nets]); hi = np.array([max(x[o] for o in ob) for ob in nets])
    ylo = np.array([min(YA[o] for o in ob) for ob in nets]); yhi = np.array([max(YA[o] for o in ob) for ob in nets])
    span = np.maximum(yhi - ylo, 1e-9)
    inb = np.clip(np.minimum(yhi, BAND[1]) - np.maximum(ylo, BAND[0]), 0, None) / span
    inb = np.where(yhi - ylo < 1e-6, ((ylo >= BAND[0]) & (ylo <= BAND[1])).astype(float), inb)
    res = {}
    for k in range(NCOL):
        xc = X0 + CW * k
        m = (lo < xc) & (hi > xc)
        res[("H", k)] = (m.sum(), (inb * m).sum(), C.Counter(ncls[j] for j in np.where(m)[0]))
    xs = np.maximum(hi - lo, 1e-9)
    for yv in YV:
        m = (ylo < yv) & (yhi > yv)
        for s in range(NCOL):
            a, b = X0 + CW * s, X0 + CW * (s + 1)
            fr = np.clip(np.minimum(hi, b) - np.maximum(lo, a), 0, None) / xs
            fr = np.where(hi - lo < 1e-6, ((lo >= a) & (lo < b)).astype(float), fr)
            v = fr * m
            cc = C.Counter()
            for j in np.where(v > 0)[0]: cc[ncls[j]] += v[j]
            res[("V%.0f" % yv, s)] = (v.sum(), v.sum(), cc)
    return res
R = {}
R["A0 identity (placed)"] = cuts(XA, "A0", None)
for o in ORD:
    for mode in os.environ.get("QB23_MODES", "A R").split():
        R["%s %s" % (mode, o)] = cuts(place(o, mode), o, None)
with open(os.path.join(od, "aff23_cuts.txt"), "w") as f:
    for key, res in R.items():
        f.write("== %s\n" % key)
        for (d, k), (n, nb, cc) in sorted(res.items()):
            tot = sum(cc.values()) or 1
            top = ", ".join("%s %.0f" % (c, 100 * v / tot) for c, v in cc.most_common(4))
            f.write("%s %d %.0f %.0f | %s\n" % (d, k, n, nb, top))
# summary: worst per cut family and per class worst-cut ratios vs the R identity reference
ref = "R " + ORD[0] if ORD[0] == "01234567" else None
fam = sorted({d for d, k in R["A0 identity (placed)"]})
print("AFF23 worst per family (H total / H band-weighted / V slots), first order = reference")
for key, res in R.items():
    w = []
    for d in fam:
        vals = [(res[(d, k)][1 if d == "H" else 0], k) for k in range(NCOL) if (d, k) in res]
        if d == "H": vals = [v for v in vals if v[1] > 0]       # interior column boundaries (k 0 = west line: order-invariant)
        v, k = max(vals); w.append("%s %.0f@%d" % (d, v, k))
    h0 = res[("H", 0)][0]
    print("AFF23 %-26s %s | west line %d" % (key, " ".join(w), h0))
if ref:
    for o in ORD[1:]:
        for mode in os.environ.get("QB23_MODES", "A R").split():
            a, b = R["%s %s" % (mode, ORD[0])], R["%s %s" % (mode, o)]
            worst = []
            for kk in a:
                ca, cb = a[kk][2], b[kk][2]; ta = sum(ca.values()) or 1
                for c in ca:
                    if ca[c] / ta >= 0.03 and ca[c] >= 100 and cb.get(c, 0) > 1.10 * ca[c]:
                        worst.append((cb.get(c, 0) / ca[c], kk, c, ca[c], cb.get(c, 0)))
            worst.sort(reverse=True)
            print("AFF23 class worse >10 %% (%s %s vs %s, classes >= 3 %% of a cut): %d; top %s" % (
                mode, o, ORD[0], len(worst), "; ".join("%s%d %s %.0f->%.0f" % (w[1][0], w[1][1], w[2], w[3], w[4]) for w in worst[:4])))
