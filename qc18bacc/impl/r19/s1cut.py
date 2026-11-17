#!/usr/bin/env python3
"""R19 estimate (builds on the PI's s1cut_pi.py): V crossings of the 15 horizontal cuts between act rows for the
QB_ACT_S1P structure (word j of all 8 slots x 2 ctx + its pre-mux in band pj[j]; S1 = per-band partial ORs + final OR
at the register's home row).  Units: tracks (one per bit-net per cut crossed), as R18 cuts.py.
Classes:
  s1p    partial ORs: one 32-b net per (reg, source band != home) from the source band to the home row (star), or
         'cascade': per reg and side, one 32-b net per cut between home and the farthest source band
  wr     write bus from the south edge: sdq word j -> band pj[j]; rdq word k -> bands of j = k mod 16 (wd = {4{rdq}})
  wer    write enables per (band, quarter present, slot) x 2 ctx: decoded in-band from broadcast fields -> ~20 nets
  s2     S2 nets (gen_act2_s2m t2): reg home -> act rows +- 1
  sel    broadcasts sel1a/b 39 x 2, sel2 11 x 2, shq 3 x 2, ctx / wer fields ~20, s1c_r 1 per band -> ~150 per cut
  res    measured R18 residual at the cut (clock, other, act pipe ...) not modelled: total - modelled R18 classes
Calibration: S2 model vs R18 measured S2 at the act-row cuts -> factor KLOC for row-local classes (fuzzy band edges,
buffers); long classes (s1p, wr) x KLONG.  Capacity at adj 0.25: 9 684 (R18 calibrated); gate 85 % = 8 231.
    python3 qc18bacc/impl/r19/s1cut.py [--seed N] [--iters N] [--out pj.txt]
"""
import argparse
import collections
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "hw", "tb"))
import gen_act2_s2m as M  # noqa: E402

NB, NJ, CAP = 16, 64, 9684
# R18 results/r18/cuts_adj0.25.txt, act-row cuts: total and the S2 share
R18_TOT = [4960, 5729, 6423, 7668, 8100, 9324, 10324, 11179, 10723, 10191, 9018, 7514, 5257, 3679, 2774]
R18_S2 = [.077, .082, .071, .062, .068, .071, .055, .049, .055, .065, .050, .051, .092, .145, .158]
# R18 listed top-7 shares per act cut (to bound the residual = classes outside the 7 listed)
R18_TOP7 = [.902, .900, .924, .903, .935, .911, .969, .975, .978, .964, .947, .992, .934, .949, .930]
R18_CLK = [.053, .052, .049, .053, .041, .034, .029, .024, .015, .038, .068, .103, .110, .119, .149]


def add(c, a, b, w):
    for k in range(min(a, b), max(a, b)):
        c[k] += w


def tables():
    regs, t1, t2 = M.build()
    return regs, t1, t2


def s1p_cuts(regs, t1, pj, cascade=False):
    c = [0] * 15
    for r in regs:
        h = r[0]
        srcs = {pj[G % NJ] for G in t1[r]}
        if cascade:
            lo, hi = min(srcs | {h}), max(srcs | {h})
            add(c, lo, h, 32)
            add(c, h, hi, 32)
        else:
            for b in srcs:
                add(c, b, h, 32)
    return c


def wr_cuts(pj):
    c = [0] * 15
    for j in range(NJ):                         # sdq word j: from the south edge (below band 0)
        add(c, 0, pj[j], 32)
    for k in range(16):                         # rdq word k -> j = k, k+16, k+32, k+48
        add(c, 0, max(pj[k + 16 * q] for q in range(4)), 32)
    return c


def s2_cuts(t2):
    c = [0] * 15
    for u, d in t2.items():
        for r in d:
            add(c, r[0], u // 9, 32)
    return c


def npairs(pj):
    return len({(pj[j], j // 16) for j in range(NJ)})


def opt(regs, t1, seed, iters, cascade, w_wr=1.0):
    """min-max of s1p + w_wr * wr over balanced pj (4 words per band) by random swaps + moves (hill climbing)."""
    rnd = random.Random(seed)
    # init: words sorted by median reader row, 4 per band
    rows = collections.defaultdict(list)
    for r in regs:
        for G in t1[r]:
            rows[G % NJ].append(r[0])
    med = {j: (sorted(rows[j])[len(rows[j]) // 2] if rows[j] else 7.5) for j in range(NJ)}
    order = sorted(range(NJ), key=lambda j: (med[j], j))
    pj = {j: i // 4 for i, j in enumerate(order)}

    def score(p):
        a, b = s1p_cuts(regs, t1, p, cascade), wr_cuts(p)
        t = [x + w_wr * y for x, y in zip(a, b)]
        return (max(t), sum(t))
    cur = score(pj)
    for _ in range(iters):
        i, j = rnd.randrange(NJ), rnd.randrange(NJ)
        if pj[i] == pj[j]:
            continue
        pj[i], pj[j] = pj[j], pj[i]
        s = score(pj)
        if s <= cur:
            cur = s
        else:
            pj[i], pj[j] = pj[j], pj[i]
    return pj


def report(regs, t1, t2, pj, cascade, KLOC, KLONG, tag):
    s1 = s1p_cuts(regs, t1, pj, cascade)
    wr = wr_cuts(pj)
    s2 = s2_cuts(t2)
    sel = [150] * 15
    res = [int(R18_TOT[k] * (1 - R18_TOP7[k]) + R18_TOT[k] * R18_CLK[k]) for k in range(15)]
    tot = [KLONG * (s1[k] + wr[k]) + KLOC * s2[k] + sel[k] + res[k] for k in range(15)]
    print(f"== {tag} ({'cascade' if cascade else 'star'}), KLOC {KLOC:.2f} KLONG {KLONG:.2f}")
    print("  cut  s1p   wr   s2  sel  res |  total   % cap0.25")
    for k in range(15):
        print(f"  {k:2d}/{k+1:<2d} {s1[k]:5d} {wr[k]:5d} {s2[k]:4d} {sel[k]:4d} {res[k]:4d} | {tot[k]:6.0f} {100*tot[k]/CAP:6.1f} %")
    m = max(tot)
    print(f"  worst {m:.0f} = {100*m/CAP:.1f} % of {CAP} (gate 85 % = {0.85*CAP:.0f}) -> {'PASS' if m <= 0.85*CAP else 'FAIL'}")
    nsrc = [len({pj[G % NJ] for G in t1[r]}) for r in regs]
    print(f"  partial outputs (reg, src band): {sum(nsrc)} (local {sum(1 for r in regs if r[0] in {pj[G % NJ] for G in t1[r]})}),"
          f" mean src bands / reg {sum(nsrc)/len(nsrc):.2f}; (band, quarter) pairs {npairs(pj)}")
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--iters", type=int, default=6000)
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    regs, t1, t2 = tables()
    s2 = s2_cuts(t2)
    meas = [R18_TOT[k] * R18_S2[k] for k in range(15)]
    KLOC = sum(meas) / sum(s2)
    print(f"S2 model {s2} vs R18 measured {[int(x) for x in meas]} -> KLOC {KLOC:.2f}")
    best = None
    for cascade in (False, True):
        pj = opt(regs, t1, a.seed, a.iters, cascade)
        for KL in (1.0, 1.3):
            m = report(regs, t1, t2, pj, cascade, KLOC, KL, f"balanced pj, 4 words / band")
        if best is None or m < best[0]:
            best = (m, cascade, pj)
    if a.out:
        m, cascade, pj = best
        with open(a.out, "w") as f:
            f.write(f"# R19 QB_ACT_S1P band map (impl/r19/s1cut.py seed {a.seed} iters {a.iters}, "
                    f"{'cascade' if cascade else 'star'}): word j -> act-row band\n")
            for j in range(NJ):
                f.write(f"{j} {pj[j]}\n")
        print("wrote", a.out)


if __name__ == "__main__":
    main()
