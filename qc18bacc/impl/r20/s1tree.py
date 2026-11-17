#!/usr/bin/env python3
"""R20 (results/r20.md): depth vs worst-cut tradeoff of the QB_ACT_S1P band-to-band OR structure (extends
impl/r19/s1cut.py: same tables, band map, cut model and calibration).
Per S1 register r (home row h, source bands S = pj of its terms) and side (bands above h = 'dn' chain, below = 'up'):
  cascade (R19)   chain h+1 .. far: every band ORs its partial into the chain (one 32-b net per cut, per reg-side)
  skip-k          stops at h +- k, h +- 2k, ...: the chain only ORs at stops; a source band between two stops sends
                  its partial express (own 32-b net) to the next stop towards h
  fold-k          as skip-k with fixed stop rows (groups of k bands: stop = group edge nearest h)
Delay model (calibrated on the r19_mc tt worst path, results/r20/cls_r19_mc.txt): band hop with an OR TOR, pure wire
hop (feed-through band, buffer) TW, partial OR in the source band TP; wide stop OR (> 3 inputs) TOR + TWIDE.
Cut model: s1p crossings of the structure + R19 write bus / S2 / selects / R18 residual (s1cut.report), x KLONG on
the long classes, capacity 9 684 tracks at adjustment 0.25; target worst <= 80 %.
    python3 qc18bacc/impl/r20/s1tree.py [--pj file] [--opt-span]
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "r19"))
sys.path.insert(0, os.path.join(HERE, "..", "..", "hw", "tb"))
import s1cut as SC          # noqa: E402
import gen_act2_s1p as SP   # noqa: E402

TOR, TW, TP, TWIDE = 0.12, 0.035, 0.0, 0.03
NB = 16


def sides(regs, t1, pj):
    out = []
    for r in regs:
        h = r[0]
        S = {pj[G % SC.NJ] for G in t1[r]}
        out.append((r, h, sorted(b for b in S if b > h), sorted((b for b in S if b < h), reverse=True)))
    return out


def stops(h, far, k, mode, sgn):
    """stop bands strictly between h and far (inclusive of far side), towards h; sgn +1 (dn side) / -1 (up side)."""
    if k <= 1:
        return None
    if mode == "skip":
        return {h + sgn * k * i for i in range(1, NB)}
    # fold: groups [g k, g k + k - 1]; stop = group edge nearest h
    return {(g * k if sgn > 0 else g * k + k - 1) for g in range(NB // k + 1)}


def side_eval(h, S, sgn, k, mode):
    """returns (delay from partial-ready to register D, list of (lo, hi) cut ranges of 32-b nets)."""
    if not S:
        return 0.0, []
    far = S[-1]
    nets = [(min(h, far), max(h, far))]          # the chain (cascade) / stop-to-stop chain: one net per cut h..far
    if k <= 1:
        # cascade: from source b, the chain passes bands b-1 .. h+1 (OR if a source, else wire), then the home OR
        worst = 0.0
        src = set(S)
        for b in S:
            d = TP
            for x in range(b - sgn, h, -sgn):
                d += TOR if x in src else TW
            worst = max(worst, d + TOR)
        return worst, nets
    if mode == "grp":                            # group g = k consecutive sources (from h outwards): stop = the member
        st = {S[i] for i in range(0, len(S), k)}  # nearest to h; the others send their partial express to it
    else:
        st = stops(h, far, k, mode, sgn)
    src = set(S)
    # chain stops actually used: stops between h and far (exclusive h) that receive something or that a source passes
    def nxt(b):                                  # next stop towards h from band b (exclusive), else h
        x = b - sgn
        while x != h:
            if x in st:
                return x
            x -= sgn
        return h
    recv = {}                                    # stop / h -> inputs
    for b in S:
        if b in st:
            recv.setdefault(b, set()).add(("p", b))
        else:
            t = nxt(b)
            recv.setdefault(t, set()).add(("p", b))
            if abs(t - b) > 0:
                nets.append((min(b, t), max(b, t)))
    worst = 0.0
    for b in S:
        tgt = b if b in st else nxt(b)
        d = TP + TW * abs(tgt - b)               # express wire to the first stop
        x = tgt
        while x != h:                            # OR at x, then wire to the next stop / h
            n = len(recv.get(x, ())) + 1
            d += TOR + (TWIDE if n > 3 else 0.0)
            y = nxt(x)
            d += TW * (abs(y - x) - 1)
            x = y
        n = len(recv.get(h, ())) + 2
        d += TOR + (TWIDE if n > 3 else 0.0)
        worst = max(worst, d)
    # the chain is only needed between h and the farthest stop that has inputs: nets above already include h..far
    return worst, nets


def side_sel(h, S, sgn, k, mode, thr):
    """mode 'grp' only where the cascade delay of this register side exceeds thr (selective grouping)."""
    d, n = side_eval(h, S, sgn, 1, "casc")
    if thr is None or d > thr:
        return side_eval(h, S, sgn, k, mode)
    return d, n


def evaluate(regs, t1, t2, pj, k, mode, KLOC, KLONG=1.0, quiet=True, thr=None):
    s1 = [0] * 15
    dl = []
    for r, h, dn, up in sides(regs, t1, pj):
        dd, nd = side_sel(h, dn, +1, k, mode, thr)
        du, nu = side_sel(h, up, -1, k, mode, thr)
        dl.append(max(dd, du))
        for lo, hi in nd + nu:
            for c in range(lo, hi):
                s1[c] += 32
    wr, s2 = SC.wr_cuts(pj), SC.s2_cuts(t2)
    res = [int(SC.R18_TOT[c] * (1 - SC.R18_TOP7[c]) + SC.R18_TOT[c] * SC.R18_CLK[c]) for c in range(15)]
    tot = [KLONG * (s1[c] + wr[c]) + KLOC * s2[c] + 150 + res[c] for c in range(15)]
    dl.sort()
    return dict(worst_cut=max(tot), pct=100 * max(tot) / SC.CAP, s1max=max(s1), dmax=dl[-1], d99=dl[int(.99 * len(dl))],
                d90=dl[int(.9 * len(dl))], n_over=sum(1 for x in dl if x > dl[-1] - 0.25))


def max_span(regs, t1, pj):
    return max(max(abs(pj[G % SC.NJ] - r[0]) for G in t1[r]) for r in regs)


def opt_span(regs, t1, t2, pj0, k, mode, KLOC, iters, seed, cap_pct=80.0):
    """swap words between bands of the same quarter purity (whole-band quarter kept): min (dmax, d99) s.t. cut <= cap."""
    import random
    rnd = random.Random(seed)
    pj = dict(pj0)
    qb = {b: {j // 16 for j in range(SC.NJ) if pj[j] == b}.pop() for b in range(NB)}

    def score(p):
        e = evaluate(regs, t1, t2, p, k, mode, KLOC)
        pen = max(0.0, e["pct"] - cap_pct)
        return (round(e["dmax"] + 0.05 * pen, 4), round(e["d99"], 4), e["pct"]), e
    cur, ce = score(pj)
    for _ in range(iters):
        if rnd.random() < 0.5:                   # swap two words of the same quarter
            i, j = rnd.randrange(SC.NJ), rnd.randrange(SC.NJ)
            if pj[i] == pj[j] or i // 16 != j // 16:
                continue
            pj[i], pj[j] = pj[j], pj[i]
            s, e = score(pj)
            if s <= cur:
                cur, ce = s, e
            else:
                pj[i], pj[j] = pj[j], pj[i]
        else:                                    # swap two whole bands (keeps purity)
            a, b = rnd.randrange(NB), rnd.randrange(NB)
            if a == b:
                continue
            old = dict(pj)
            for j in range(SC.NJ):
                pj[j] = b if old[j] == a else a if old[j] == b else old[j]
            s, e = score(pj)
            if s <= cur:
                cur, ce = s, e
            else:
                pj = old
    return pj, ce


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--opt", action="store_true", help="optimise the band map per structure")
    ap.add_argument("--iters", type=int, default=3000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default="")
    ap.add_argument("--k", type=int, default=0)
    ap.add_argument("--mode", default="skip")
    ap.add_argument("--grp", default="", help="write the selective grp-2 side list (thr --thr) for gen_act2_s1t.py")
    ap.add_argument("--thr", type=float, default=1.0)
    ap.add_argument("--pt", default="", help="per-register PT slack list (results/r20/s1_slack_r19mc_tt.txt)")
    ap.add_argument("--ptthr", type=float, default=-0.05)
    ap.add_argument("--cap", type=float, default=80.0)
    a = ap.parse_args()
    regs, t1, t2 = SC.tables()
    pj, _, _ = SP.load_pj()
    if a.grp:
        s2 = SC.s2_cuts(t2)
        KLOC = sum(SC.R18_TOT[c] * SC.R18_S2[c] for c in range(15)) / sum(s2)
        sd = sides(regs, t1, pj)
        home_k = {}
        for i, (r, h, dn, up) in enumerate(sd):
            home_k[(h, sum(1 for x in regs[:i] if x[0] == h))] = i
        sel = {(i, nm) for i, (r, h, dn, up) in enumerate(sd) for nm, S, sg in (("dn", dn, +1), ("up", up, -1))
               if side_eval(h, S, sg, 1, "casc")[0] > a.thr}

        def pct(sel):
            s1 = [0] * 15
            for i, (r, h, dn, up) in enumerate(sd):
                for nm, S, sg in (("dn", dn, +1), ("up", up, -1)):
                    _, n = side_eval(h, S, sg, 2, "grp") if (i, nm) in sel else side_eval(h, S, sg, 1, "casc")
                    for lo, hi in n:
                        for c in range(lo, hi):
                            s1[c] += 32
            wr, res = SC.wr_cuts(pj), [int(SC.R18_TOT[c] * (1 - SC.R18_TOP7[c]) + SC.R18_TOT[c] * SC.R18_CLK[c]) for c in range(15)]
            return 100 * max(1.3 * (s1[c] + wr[c]) + KLOC * s2[c] + 150 + res[c] for c in range(15)) / SC.CAP
        npt = 0
        if a.pt:                                 # add the measured critical registers' long sides while the cut <= a.cap
            crit = sorted((float(l.split()[3]), int(l.split()[1]), int(l.split()[2])) for l in open(a.pt) if l.startswith("s1 "))
            for s, h, k in crit:
                if s >= a.ptthr:
                    break
                i = home_k[(h, k)]
                r, h, dn, up = sd[i]
                cand = [(side_eval(h, S, sg, 1, "casc")[0], nm) for nm, S, sg in (("dn", dn, +1), ("up", up, -1)) if len(S) >= 3]
                for _, nm in sorted(cand, reverse=True)[:1]:
                    if (i, nm) not in sel and pct(sel | {(i, nm)}) <= a.cap:
                        sel.add((i, nm)); npt += 1
        with open(a.grp, "w") as f:
            f.write(f"# R20 QB_ACT_S1T grouped register sides (impl/r20/s1tree.py --grp: grp-2 where the R19 cascade model delay"
                    f" > {a.thr} ns (TOR {TOR} TW {TW}), + {npt} long sides of registers with r19_mc tt slack < {a.ptthr} at"
                    f" 489.6 MHz while the modelled worst cut (x1.3) <= {a.cap} %): register index (qba2_s1r order), side\n")
            for i, nm in sorted(sel):
                f.write(f"{i} {nm}\n")
        print(f"wrote {a.grp}: {len(sel)} grouped sides ({npt} from the PT list), modelled worst cut x1.3 {pct(sel):.1f} %")
        return
    s2 = SC.s2_cuts(t2)
    KLOC = sum(SC.R18_TOT[c] * SC.R18_S2[c] for c in range(15)) / sum(s2)
    print(f"model TOR {TOR} TW {TW} TWIDE {TWIDE}; R19 band map max span {max_span(regs, t1, pj)}")
    print(f"{'structure':14s} {'map':6s} {'dmax':>6s} {'d99':>6s} {'d90':>6s} {'s1max':>6s} {'cut%':>6s} {'cut%x1.3':>8s}")
    cfgs = [(1, "casc")] + [(k, m) for m in ("skip", "fold", "grp") for k in (2, 3, 4)] if not a.k else [(a.k, a.mode)]
    for k in (2, 3):
        for thr in (0.6, 0.7, 0.8, 0.9, 1.0):
            e = evaluate(regs, t1, t2, pj, k, "grp", KLOC, thr=thr)
            e13 = evaluate(regs, t1, t2, pj, k, "grp", KLOC, KLONG=1.3, thr=thr)
            print(f"{'grp-%d>%.1f' % (k, thr):14s} {'r19':6s} {e['dmax']:6.3f} {e['d99']:6.3f} {e['d90']:6.3f} {e['s1max']:6d} {e['pct']:6.1f} {e13['pct']:8.1f}")
    for k, m in cfgs:
        e = evaluate(regs, t1, t2, pj, k, m, KLOC)
        e13 = evaluate(regs, t1, t2, pj, k, m, KLOC, KLONG=1.3)
        print(f"{m + '-' + str(k):14s} {'r19':6s} {e['dmax']:6.3f} {e['d99']:6.3f} {e['d90']:6.3f} {e['s1max']:6d} {e['pct']:6.1f} {e13['pct']:8.1f}")
        if a.opt:
            p2, e2 = opt_span(regs, t1, t2, pj, k, m, KLOC, a.iters, a.seed)
            e213 = evaluate(regs, t1, t2, p2, k, m, KLOC, KLONG=1.3)
            print(f"{m + '-' + str(k):14s} {'opt':6s} {e2['dmax']:6.3f} {e2['d99']:6.3f} {e2['d90']:6.3f} {e2['s1max']:6d} {e2['pct']:6.1f} {e213['pct']:8.1f}  span {max_span(regs, t1, p2)}")
            if a.out and a.k:
                with open(a.out, "w") as f:
                    f.write(f"# R20 band map (impl/r20/s1tree.py --opt --k {k} --mode {m} seed {a.seed} iters {a.iters}): word j -> act-row band\n")
                    for j in range(SC.NJ):
                        f.write(f"{j} {p2[j]}\n")
                print("wrote", a.out)


if __name__ == "__main__":
    main()
