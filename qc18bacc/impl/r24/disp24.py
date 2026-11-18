#!/usr/bin/env python3
"""R24 (results/r24.md): legalisation displacement of post-CTS repair cells (H1 local density vs H2 over macros).
usage: disp24.py <r24 dir> <a> <b> [prev]   dumps d_<a>.txt (unlegalised), d_<b>.txt (after DPL), d_<prev>.txt (before
the repair; default: sl for a=hu, pre for a=su) + geom.txt (dump24.tcl).  Touched = new instance or master changed vs prev.
Per cell: pre-legal centre over a macro (bbox + HALO um) or not, local density of its 50 um bin (std-cell area in d_<a> /
free site area = core minus macros + halo), DPL displacement (manhattan um).  Prints < 30 lines."""
import sys, os
import numpy as np

HALO, BIN, RES = 7.0, 50.0, 2.0


def load(p):
    d = {}
    with open(p) as f:
        for l in f:
            t = l.split()
            d[t[0]] = (t[1], int(t[2]), int(t[3]), int(t[4]), int(t[5]), t[6])
    return d


def main():
    D, a, b = sys.argv[1:4]
    prev = sys.argv[4] if len(sys.argv) > 4 else {"hu": "sl", "su": "pre"}.get(a, "sl")
    g = [l.split() for l in open(os.path.join(D, "geom.txt"))]
    U = float(next(t[1] for t in g if t[0] == "U"))
    cx0, cy0, cx1, cy1 = (int(v) / U for v in next(t[1:5] for t in g if t[0] == "C"))
    mac = np.array([[int(v) / U for v in t[2:6]] for t in g if t[0] == "M"])
    A, Bd = load(os.path.join(D, f"d_{a}.txt")), load(os.path.join(D, f"d_{b}.txt"))
    P = load(os.path.join(D, f"d_{prev}.txt")) if os.path.exists(os.path.join(D, f"d_{prev}.txt")) else {}
    # free-site mask at RES um, binned to BIN
    nx, ny = int(np.ceil(cx1 / RES)), int(np.ceil(cy1 / RES))
    free = np.zeros((nx, ny), bool)
    free[int(cx0 / RES):int(cx1 / RES), int(cy0 / RES):int(cy1 / RES)] = True
    for x0, y0, x1, y1 in mac:
        free[max(0, int((x0 - HALO) / RES)):int(np.ceil((x1 + HALO) / RES)), max(0, int((y0 - HALO) / RES)):int(np.ceil((y1 + HALO) / RES))] = False
    k = int(BIN / RES)
    bx, by = nx // k + 1, ny // k + 1
    fp = np.zeros((bx * k, by * k), bool); fp[:nx, :ny] = free
    farea = fp.reshape(bx, k, by, k).sum(axis=(1, 3)) * RES * RES
    names = list(A)
    xa = np.array([(A[n][1] + A[n][3] / 2) / U for n in names]); ya = np.array([(A[n][2] + A[n][4] / 2) / U for n in names])
    ar = np.array([A[n][3] * A[n][4] for n in names]) / U / U
    ib, jb = np.clip((xa / BIN).astype(int), 0, bx - 1), np.clip((ya / BIN).astype(int), 0, by - 1)
    sarea = np.zeros((bx, by)); np.add.at(sarea, (ib, jb), ar)
    dens = np.where(farea > 0.1 * BIN * BIN, sarea / np.maximum(farea, 1), np.inf)
    cd = dens[ib, jb]
    om = np.zeros(len(names), bool)
    mname = [t[1] for t in g if t[0] == "M"]
    mid = np.full(len(names), -1)
    for k, (x0, y0, x1, y1) in enumerate(mac):
        hit = (xa > x0 - HALO) & (xa < x1 + HALO) & (ya > y0 - HALO) & (ya < y1 + HALO)
        om |= hit; mid[hit] = k
    disp = np.array([(abs(Bd[n][1] - A[n][1]) + abs(Bd[n][2] - A[n][2])) / U if n in Bd else 0.0 for n in names])
    tch = np.array([(n not in P) or (P[n][0] != A[n][0]) for n in names]) if P else np.zeros(len(names), bool)
    new = np.array([n not in P for n in names]) if P else np.zeros(len(names), bool)
    tot = disp.sum()
    print(f"R24_DISP {a}->{b} prev {prev}: cells {len(names)} touched {tch.sum()} (new {new.sum()}) total_disp_um {tot:.0f} "
          f"mean {disp.mean():.2f} max {disp.max():.1f}  [M]")
    print(f"  touched disp {disp[tch].sum():.0f} ({100*disp[tch].sum()/max(tot,1):.1f} %), untouched (pushed) {disp[~tch].sum():.0f}")
    for lab, m in (("H2 touched over macro", tch & om), ("touched not over macro", tch & ~om), ("untouched over macro", ~tch & om)):
        print(f"  {lab}: n {m.sum()} disp {disp[m].sum():.0f} ({100*disp[m].sum()/max(tot,1):.1f} %) mean {disp[m].mean() if m.any() else 0:.1f}")
    edges = [0, 0.6, 0.7, 0.8, 0.9, 1.0, 1.2, np.inf]
    print("  bin density (50 um, pre-legal) | touched n / disp % / mean | all cells n / disp %  (cells not over macro)")
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = ~om & (cd >= lo) & (cd < hi)
        mt = m & tch
        print(f"   {lo:4.1f}-{hi:<4.1f}  {mt.sum():7d} {100*disp[mt].sum()/max(tot,1):6.1f} % {disp[mt].mean() if mt.any() else 0:6.1f}"
              f" | {m.sum():7d} {100*disp[m].sum()/max(tot,1):6.1f} %")
    he = [0, 2, 5, 20, 50, 100, 200, 400, 1e9]
    h = np.histogram(disp[tch], he)[0]; hu = np.histogram(disp[~tch], he)[0]
    print("  disp hist um " + " ".join(f"{int(lo)}-:{c}/{cu}" for lo, c, cu in zip(he[:-1], h, hu)) + "  (touched/untouched)")
    fin = np.isfinite(dens) & (farea > 0)
    print(f"  bins: density p50 {np.percentile(dens[fin], 50):.2f} p90 {np.percentile(dens[fin], 90):.2f} p99 "
          f"{np.percentile(dens[fin], 99):.2f} max {dens[fin].max():.2f}; bins > 1.0: {(dens[fin] > 1).sum()} of {fin.sum()}")
    bd = np.zeros((bx, by)); np.add.at(bd, (ib, jb), disp)
    for f in np.argsort(bd.ravel())[::-1][:4]:
        i, j = np.unravel_index(f, bd.shape)
        print(f"  hot bin x {i*BIN:.0f} y {j*BIN:.0f}: disp {bd[i,j]:.0f} ({100*bd[i,j]/max(tot,1):.1f} %) density {dens[i,j]:.2f} "
              f"free {farea[i,j]:.0f} um2 touched {int((tch & (ib == i) & (jb == j)).sum())}")
    mc = {}
    for k in mid[tch & om]:
        n = mname[k].split("/")[-1]; mc[n] = mc.get(n, 0) + 1
    print("  touched-over-macro by macro: " + " ".join(f"{m}:{c}" for m, c in sorted(mc.items(), key=lambda x: -x[1])[:6]))
    # masters of touched cells
    ms = {}
    for n, t in zip(names, tch):
        if t: ms[A[n][0]] = ms.get(A[n][0], 0) + 1
    print("  touched masters: " + " ".join(f"{m}:{c}" for m, c in sorted(ms.items(), key=lambda x: -x[1])[:8]))


if __name__ == "__main__":
    main()
