#!/usr/bin/env python3
"""R17 step 1 (offline, no EDA): feasibility of a per-layout line-buffer word placement (QB_ACT_LBP idea).

Model (results/r17.md section 1):
  * act rows 0..15 at y = row; S1 register (h, j) of the row-homed S1 (gen_act2_s2m.build) sits at row h.
  * line buffer: 8 slots x 64 groups (32 b); the slot shift moves slot s + k -> s, so every slot of one in-slot index j
    (and both contexts + the pre-mux) is one physical column of flops at one row: a permutation must act on j only,
    identically for all slots (it then commutes with the shift).
  * layout key L(c, l) = the pass kind that wrote the line buffer: cfg 0 / 1 share a pass (A), int8 lines 33..38 are
    layouts 8i / 9i / 10i, binary cfg 10 (b7) is 10b.  The write side knows L from the latched pass command.
  * crossings of horizontal cuts between act rows = bits x rows spanned:
      S1 net of physical word (s, P): 32 x span(reader home rows U {row of P})
      write net: rdq group k / sdq group j: 32 x span(rows of the P it can be written to)       (source free)
                 + variant with the source pinned at the south edge (row 16 or row -1)
  * "current" = no permutation (P = j), word row = best row for its readers (consistent over slots);
    "PI metric" = per word (s, j) span of readers only (word free per slot, as s1geo.py).
    python3 -I qc18bacc/impl/r17/lbp_feas.py [--emit]      (from the repo root or qc18bacc)
"""
import itertools
import os
import statistics as st
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "hw", "tb"))
import gen_act2_s2m as M  # noqa: E402

import numpy as np                                  # noqa: E402
from scipy.optimize import linear_sum_assignment    # noqa: E402

ROWS, NJ, PERROW = 16, 64, 4
BIN_L = ["A", "2", "3", "4", "5", "6", "7", "10b"]
INT_L = ["8i", "9i", "10i"]
LAYOUTS = BIN_L + INT_L


def lay(c, l):
    if l >= 33:
        return {33: "8i", 34: "9i"}.get(l, "10i")
    if c in (0, 1):
        return "A"
    return "10b" if c == 10 else str(c)


def span(rows):
    return max(rows) - min(rows) if rows else 0


def readers():
    """R[L][j][s] = set of reader home rows; also the S1 tables."""
    regs, t1, t2 = M.build()
    R = {L: defaultdict(lambda: defaultdict(set)) for L in LAYOUTS}
    for r in regs:
        for G, prs in t1[r].items():
            for c, l in prs:
                R[lay(c, l)][G % 64][G // 64].add(r[0])
    return regs, t1, t2, R


def place(R, prev=None, t1=None, regs=None):
    """per layout: j -> P (bijection 64 -> 64), P's row = P // 4.  Rows by min-cost assignment (cost = summed S1
    span of the j's slots if placed at row y); inside a row the 4 positions are matched to maximise S1 term sharing
    with the layouts already placed (register reads the same physical word under several layouts)."""
    pi = {}
    # S1 sharing state: register -> set of physical G already read
    reads = defaultdict(set)
    jr = defaultdict(lambda: defaultdict(set))     # (L, s, j) -> registers
    for r in regs:
        for G, prs in t1[r].items():
            for c, l in prs:
                jr[lay(c, l)][(G // 64, G % 64)].add(r)
    order = ["A", "4", "7", "10b", "2", "5", "8i", "10i", "9i", "3", "6"]
    for L in order:
        cost = np.zeros((NJ, ROWS * PERROW))
        for j in range(NJ):
            for y in range(ROWS):
                cst = sum(span(rs | {y}) for rs in R[L][j].values())
                cost[j, PERROW * y:PERROW * y + PERROW] = cst
        jj, cc = linear_sum_assignment(cost)
        rowof = {j: c // PERROW for j, c in zip(jj, cc)}
        p = {}
        for y in range(ROWS):
            js = sorted(j for j in range(NJ) if rowof[j] == y)
            best = None
            for perm in itertools.permutations(range(PERROW)):
                sc = 0
                for j, k in zip(js, perm):
                    P = PERROW * y + k
                    for (s, jj2), rs in jr[L].items():
                        if jj2 == j:
                            sc += sum(1 for r in rs if s * 64 + P in reads[r])
                if best is None or sc > best[0]:
                    best = (sc, perm)
            for j, k in zip(js, best[1]):
                p[j] = PERROW * y + k
        pi[L] = p
        for (s, j), rs in jr[L].items():
            for r in rs:
                reads[r].add(s * 64 + p[j])
    return pi


def s1_cross_new(R, pi):
    """S1 crossings with the permutation: physical word (s, P) at row P // 4; readers = union over layouts."""
    rd = defaultdict(set)
    for L in LAYOUTS:
        for j, bys in R[L].items():
            for s, rs in bys.items():
                rd[(s, pi[L][j])] |= rs
    tot = sum(32 * span(rs | {P // PERROW}) for (s, P), rs in rd.items())
    return tot, rd


def s1_cross_cur(R):
    rd = defaultdict(set)
    for L in LAYOUTS:
        for j, bys in R[L].items():
            for s, rs in bys.items():
                rd[(s, j)] |= rs
    pi_metric = sum(32 * span(rs) for rs in rd.values())
    # consistent: index j (all slots) at one row y_j minimising its S1 crossings
    yj, cons = {}, 0
    for j in range(NJ):
        best = min(range(ROWS), key=lambda y: sum(span(rd[(s, j)] | {y}) for s in range(8) if rd.get((s, j))))
        yj[j] = best
        cons += 32 * sum(span(rd[(s, j)] | {best}) for s in range(8) if rd.get((s, j)))
    return pi_metric, cons, yj, rd


def write_net(rowP, cand, south=None):
    """cand[src] = set of physical P it may be written to; crossings = 32 x span(rows (+ south))."""
    tot = 0
    for src, Ps in cand.items():
        rows = {rowP(P) for P in Ps}
        if south is not None:
            rows.add(south)
        tot += 32 * span(rows)
    return tot


def write_cands(pi):
    """binary: rdq group k -> P with pi_L(16 q + k) for binary L; int8: sdq group j -> pi_L(j) for int8 L.
    per P: distinct (source) candidates."""
    src = defaultdict(set)
    perP = defaultdict(set)
    for L in BIN_L:
        for j in range(NJ):
            P = pi[L][j]
            src[("r", j % 16)].add(P)
            perP[P].add(("r", j % 16))
    for L in INT_L:
        for j in range(NJ):
            P = pi[L][j]
            src[("s", j)].add(P)
            perP[P].add(("s", j))
    return src, perP


def s1_terms(regs, t1, pi):
    before = [len(t1[r]) for r in regs]
    after = []
    for r in regs:
        g = set()
        for G, prs in t1[r].items():
            for c, l in prs:
                g.add((G // 64) * 64 + pi[lay(c, l)][G % 64])
        after.append(len(g))
    return before, after


def main():
    regs, t1, t2, R = readers()
    # 1. slot dependence: per layout, words whose reader rows differ between slots
    print("== slot dependence of the reader rows (per layout L, in-slot index j)")
    for L in LAYOUTS:
        nj = len(R[L])
        dep = [j for j, bys in R[L].items() if len({frozenset(v) for v in bys.values()}) > 1]
        multi = sum(1 for bys in R[L].values() for v in bys.values() if len(v) > 1)
        nw = sum(len(bys) for bys in R[L].values())
        ext = [span(set().union(*bys.values())) for bys in R[L].values()]
        print(f"  {L:>3}: j used {nj:2d}, words {nw:3d}, j with slot-dependent readers {len(dep):2d}, "
              f"multi-reader words {multi:3d}; span over slots of j: mean {st.mean(ext):.2f} max {max(ext)}")
    ident = {L: {j: j for j in range(NJ)} for L in LAYOUTS}
    pim, cons, yj, rd0 = s1_cross_cur(R)
    pi = place(R, t1=t1, regs=regs)
    new, rd1 = s1_cross_new(R, pi)
    # lower bounds for ANY permutation: the union span of a physical word >= the span of each layout's word in it, so
    # new S1 >= max over layouts of that layout's own optimum; (a) slot-independent permutation (one row per j),
    # (b) even a slot-dependent placement (each (s, j) free; does not commute with the shift) keeps the within-word span
    lb_a = {L: sum(32 * min(sum(span(rs | {y}) for rs in bys.values()) for y in range(ROWS)) for bys in R[L].values())
            for L in LAYOUTS}
    lb_b = {L: sum(32 * span(rs) for bys in R[L].values() for rs in bys.values()) for L in LAYOUTS}
    print("== S1 crossings (32 b x rows spanned, summed over physical words)")
    print(f"  current, PI metric (word free per slot)          {pim:8d}")
    print(f"  current, consistent (index j at one row)        {cons:8d}")
    print(f"  new LBP (P at row P // 4)                       {new:8d}   ({100 * (new / cons - 1):+.1f} % vs consistent)")
    La, Lb = max(lb_a, key=lb_a.get), max(lb_b, key=lb_b.get)
    print(f"  lower bound, any slot-independent permutation   {lb_a[La]:8d}   (layout {La} alone; {100 * (1 - lb_a[La] / cons):.1f} % below current)")
    print(f"  lower bound, even slot-dependent placement      {lb_b[Lb]:8d}   (layout {Lb}: within-word spans)")
    print("  per-layout own optimum (slot-independent) / within-word span:",
          ", ".join(f"{L} {lb_a[L]}/{lb_b[L]}" for L in LAYOUTS))
    # residual: new crossings by layout of origin
    print("  residual by layout (new crossings of the words of one layout alone):")
    for L in LAYOUTS:
        x = sum(32 * span(rs | {pi[L][j] // PERROW}) for j, bys in R[L].items() for rs in bys.values())
        print(f"    {L:>3}: {x:7d}")
    # write network
    src0, perP0 = write_cands(ident)
    src1, perP1 = write_cands(pi)
    print("== write network (per context; both contexts share the rows)")
    for nm, src, rowP in (("current", src0, lambda P: yj[P]), ("LBP", src1, lambda P: P // PERROW)):
        w = write_net(rowP, src)
        ws = [write_net(rowP, src, south=sv) for sv in (-1, 16)]
        print(f"  {nm:8s}: crossings {w:7d} (source free), with south pin at row -1 / 16: {ws[0]} / {ws[1]}")
    c0 = [len(v) for v in perP0.values()]
    c1 = [len(perP1[P]) for P in range(NJ)]
    print(f"  candidates per physical word: current max {max(c0)} mean {st.mean(c0):.2f}; "
          f"LBP max {max(c1)} mean {st.mean(c1):.2f} (rdq groups + sdq groups, + zero)")
    nb = [len({p for p in perP1[P] if p[0] == 'r'}) for P in range(NJ)]
    ns = [len({p for p in perP1[P] if p[0] == 's'}) for P in range(NJ)]
    print(f"    LBP binary (rdq) candidates per P: max {max(nb)} mean {st.mean(nb):.2f}; int8 (sdq): max {max(ns)} "
          f"mean {st.mean(ns):.2f}")
    # S1 fan-in
    b, a = s1_terms(regs, t1, pi)
    print("== S1 terms per register (row-homed S1 registers / S2 unchanged; source words renamed)")
    print(f"  before: total {sum(b)} mean {st.mean(b):.2f} max {max(b)}; after: total {sum(a)} mean {st.mean(a):.2f} "
          f"max {max(a)}  (x{sum(a) / sum(b):.2f} total, x{max(a) / max(b):.2f} max)")
    # decision
    wcur = write_net(lambda P: yj[P], src0)
    wnew = write_net(lambda P: P // PERROW, src1)
    totc, totn = cons + wcur, new + wnew
    totp = pim + wcur
    print("== decision (S1 + write crossings)")
    print(f"  S1 only: {cons} -> {new} ({100 * (1 - new / cons):.1f} % drop); bound {100 * (1 - lb_a[La] / cons):.1f} %")
    print(f"  current {totc} (PI-metric S1: {totp}) -> LBP {totn}: {100 * (1 - totn / totc):.1f} % drop "
          f"({100 * (1 - totn / totp):.1f} % vs PI-metric); fan-in x{sum(a) / sum(b):.2f}")
    ok = (1 - totn / totc) >= 0.40 and sum(a) / sum(b) <= 1.3
    print(f"  rule (>= 40 % drop and fan-in <= 1.3x): {'CONTINUE' if ok else 'STOP'}")
    return pi


if __name__ == "__main__":
    main()
