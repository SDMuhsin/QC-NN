#!/usr/bin/env python3
"""R23 (results/r23.md): exhaustive column-order search under the aff23.py model A (std cells move with the column
slot they sit under; S lane L -> column L % 8, params k -> column k, hub ports at x >= 860 -> their column; B macros,
west-strip ports / macros stay at their physical slot).  Nets are reduced to signatures (logical column mask, fixed
slot range); a cut x = 860 + 390 k (k 1..7) is crossed iff the signature's slot span contains it.  All 8! orders.
    python3 -I aff23s.py <aff23 dump> [top N 8]  -> stdout (< 30 lines)"""
import itertools, os, re, sys, collections as C
import numpy as np
fd = sys.argv[1]; TOP = int(sys.argv[2]) if len(sys.argv) > 2 else 8
X0, CW = 860.0, 390.0
BAND = tuple(map(float, os.environ.get("QB23_BAND", "848 1485").split()))
MAXD = int(os.environ.get("QB23_MAXD", "1000000"))
slot = lambda x: -1 if x < X0 else min(int((x - X0) // CW), 7)
SIG = {}
icol, ifix, iy = [], [], []                                  # per instance: logical column or -1, fixed slot or None, y
for ln in open(fd):
    t = ln.split()
    if t[0] == "I":
        x, y = float(t[3]), float(t[4]); iy.append(y)
        c, f = -1, None
        if t[5] == "1":
            m = re.search(r"g_s_(\d+)__u_m", t[6]); p = re.search(r"g_pm_(\d+)_", t[6])
            if m: c = int(m.group(1)) % 8
            elif p and int(p.group(1)) < 8: c = int(p.group(1))
            else: f = slot(x)
        else:
            s = slot(x)
            if s >= 0: c = s
            else: f = -1
        icol.append(c); ifix.append(f)
        continue
    if t[0] != "N": continue
    if len(t) - 2 > MAXD: continue
    mask, fl, fh, ylo, yhi = 0, 99, -99, 1e9, -1e9
    for tk in t[2:]:
        if tk[0] == "p":
            a, b = map(float, tk[1:].split(":")); s = slot(a); y = b
            if s >= 0: mask |= 1 << s
            else: fl, fh = min(fl, -1), max(fh, -1)
        else:
            i = int(tk); y = iy[i]
            if icol[i] >= 0: mask |= 1 << icol[i]
            else: fl, fh = min(fl, ifix[i]), max(fh, ifix[i])
        ylo, yhi = min(ylo, y), max(yhi, y)
    sp = yhi - ylo
    wb = (1.0 if BAND[0] <= ylo <= BAND[1] else 0.0) if sp < 1e-6 else max(0.0, min(yhi, BAND[1]) - max(ylo, BAND[0])) / sp
    key = (mask, fl, fh)
    sig = SIG.setdefault(key, [0, 0.0])
    sig[0] += 1; sig[1] += wb
keys = list(SIG); n = len(keys)
M = np.array([[(k[0] >> c) & 1 for c in range(8)] for k in keys], bool)
FL = np.array([k[1] for k in keys]); FH = np.array([k[2] for k in keys])
WT = np.array([SIG[k][0] for k in keys], float); WB = np.array([SIG[k][1] for k in keys])
print("AFF23S signatures %d, nets %d" % (n, WT.sum()))
def evalo(order):
    pos = np.empty(8, int); pos[list(order)] = np.arange(8)
    P = np.where(M, pos[None, :], 99); lo = np.minimum(P.min(1), FL)
    P = np.where(M, pos[None, :], -99); hi = np.maximum(P.max(1), FH)
    ks = np.arange(1, 8)
    cr = (lo[:, None] < ks[None, :]) & (hi[:, None] >= ks[None, :])
    return WB @ cr, WT @ cr
res = []
for o in itertools.permutations(range(8)):
    b, t = evalo(o)
    res.append((b.max(), t.max(), o))
res.sort()
idb, idt = evalo(tuple(range(8)))
fmt = lambda o: "".join(map(str, o))
print("AFF23S identity: band-weighted H per cut k1..7 %s (max %.0f); total max %.0f" % (" ".join("%.0f" % v for v in idb), idb.max(), idt.max()))
for name in ("04152637", "40516273"):
    b, t = evalo(tuple(int(c) for c in name))
    print("AFF23S %s: band-weighted max %.0f (%+.1f %%), total max %.0f (%+.1f %%)" % (name, b.max(), 100 * (b.max() / idb.max() - 1), t.max(), 100 * (t.max() / idt.max() - 1)))
print("AFF23S best %d of %d orders by worst band-weighted interior cut:" % (TOP, len(res)))
for b, t, o in res[:TOP]:
    bb, _ = evalo(o)
    print("AFF23S   %s  band max %.0f (%+.1f %%)  total max %.0f (%+.1f %%)  cuts %s" % (fmt(o), b, 100 * (b / idb.max() - 1), t, 100 * (t / idt.max() - 1), " ".join("%.0f" % v for v in bb)))
rank = [r[2] for r in res].index(tuple(range(8)))
print("AFF23S identity rank %d of %d" % (rank + 1, len(res)))
