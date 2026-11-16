#!/usr/bin/env python3
"""R8c: wire-demand model of S2 (S1 -> act) and of the row-homed S1 / S2 (QB_ACT_S2M, hw/tb/gen_act2_s2m.py), on top of
R8b's pre-mux (QB_ACT_S1M = 1).  Same 1-D placement model as impl/r8b/model.py (act rows fixed at column 0's act-pin y,
S / map pins south, quadratic placement with rank spreading), nets: sdq / rdq -> LB, LB Q (shift + pre-mux), pre-mux
out -> S1, S1 -> act (S2).  Also: (1) S2 mechanism = act-row span of every R2 S1 group by configuration pair.
    python3 qc18bacc/impl/r8c/model.py
"""
import os
import sys
from collections import defaultdict

import numpy as np

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, "..", "r8b"))
sys.path.insert(0, os.path.join(here, "..", "..", "hw", "tb"))
import model as M8          # noqa: E402  (impl/r8b/model.py)
import gen_act2_s2m as SR   # noqa: E402

TAPS = 9


def variant(v):
    """-> (S1 reg list, reg -> LB groups, reg -> act units)"""
    if v == "a":
        s1, s2 = SR.ref()
        rd = defaultdict(set)
        for u in range(144):
            for p in s2[u]:
                rd[p].add(u)
        return sorted(s1), {p: set(s1[p]) for p in s1}, rd
    regs, t1, t2 = SR.build()
    rd = defaultdict(set)
    for u in range(144):
        for r in t2[u]:
            rd[r].add(u)
    return regs, {r: set(t1[r]) for r in regs}, rd


def place(v, iters=150, seed=1, H=M8.H):
    regs, src, rd = variant(v)
    rng = np.random.default_rng(seed)
    nodes, fixed, nets = {}, {}, []
    def node(k, a):
        if k not in nodes:
            nodes[k] = (len(nodes), a)
        return nodes[k][0]
    for u in range(144):
        fixed[node(("act", u), 0.0)] = M8.ROWY[u // TAPS]
    for j in range(64):
        pin = node(("pin_s", j), 0.0); fixed[pin] = 0.0
        sq = node(("sdq", j), 32 * 6.5)
        nets.append(([pin, sq], 32, "S/map in"))
        nets.append(([sq] + [node(("lb", c, 64 * s + j), 440.0) for c in (0, 1) for s in range(8)], 32, "sdq/rdq -> LB"))
    for i in range(16):
        pin = node(("pin_m", i), 0.0); fixed[pin] = 0.0
        rq = node(("rdq", i), 32 * 6.5)
        nets.append(([pin, rq], 32, "S/map in"))
        nets.append(([rq] + [node(("lb", c, 64 * s + g), 440.0) for c in (0, 1) for s in range(8)
                             for g in range(64) if g % 16 == i], 32, "sdq/rdq -> LB"))
    a_s1 = 900.0 * 192 / len(regs) * (sum(len(x) for x in src.values()) / 1244)   # S1 cell area ~ terms
    for c in (0, 1):
        for s in range(8):
            for j in range(64):
                g = 64 * s + j
                d = [node(("lb", c, 64 * (s - k) + j), 440.0) for k in (1, 2, 4) if s - k >= 0]
                d.append(node(("m", g), 32 * 3.6))
                nets.append(([node(("lb", c, g), 440.0)] + d, 32, "LB Q (shift + premux)"))
    snk = defaultdict(list)
    for r in regs:
        for g in src[r]:
            snk[g].append(node(("s1", r), a_s1))
    for g, d in snk.items():
        nets.append(([node(("m", g), 32 * 3.6)] + d, 32, "premux out -> S1"))
    for r in regs:
        nets.append(([node(("s1", r), a_s1)] + [nodes[("act", u)][0] for u in sorted(rd[r])], 32, "S1 -> act (S2)"))
    n = len(nodes)
    A = np.zeros(n); isf = np.zeros(n, bool); y = rng.uniform(0, H, n)
    for k, (i, a) in nodes.items():
        A[i] = a
    for i, val in fixed.items():
        isf[i] = True; y[i] = val
    mov = np.where(~isf)[0]
    for it in range(iters):
        acc = np.zeros(n); ws = np.zeros(n)
        for pins, b, _ in nets:
            cc = y[pins].mean(); w = b / max(1, len(pins) - 1)
            acc[pins] += w * cc; ws[pins] += w
        tgt = np.where(ws > 0, acc / np.maximum(ws, 1e-9), y)
        yn = 0.5 * y + 0.5 * tgt
        o = mov[np.argsort(yn[mov])]
        spread = (np.cumsum(A[o]) - A[o] / 2) / A[o].sum() * H
        y[o] = 0.6 * yn[o] + 0.4 * spread if it < iters - 1 else spread
    wl = 0.0; wc = defaultdict(float); cut = np.zeros(int(H // 10) + 2)
    for pins, b, cl in nets:
        lo, hi = y[pins].min(), y[pins].max()
        wl += b * (hi - lo); wc[cl] += b * (hi - lo)
        cut[int(lo // 10):int(hi // 10) + 1] += b
    return wl, cut, wc


def mechanism():
    s1, s2 = SR.ref()
    rows = defaultdict(lambda: defaultdict(set))
    for u in range(144):
        for p, cs in s2[u].items():
            for c in cs:
                rows[p][c].add(u // TAPS)
    span = [max(r for c in rows[p] for r in rows[p][c]) - min(r for c in rows[p] for r in rows[p][c]) for p in rows]
    print(f"R2 S1 groups read by S2: {len(rows)}; act-row span (rows, 120 um each) mean {np.mean(span):.2f} "
          f"max {max(span)}; hist {dict(sorted({k: span.count(k) for k in set(span)}.items()))}")
    # span if only a configuration class were kept
    cls = {"stride-1 3x3 (0 1 4 7 10)": {0, 1, 4, 7, 10}, "stride-2 3x3 (2 5 8)": {2, 5, 8},
           "1x1 gathers (3 6 9)": {3, 6, 9}}
    for n, cs in cls.items():
        sp = [max(r for c in rows[p] if c in cs for r in rows[p][c]) - min(r for c in rows[p] if c in cs
              for r in rows[p][c]) for p in rows if any(c in cs for c in rows[p])]
        print(f"  {n:26s} alone: groups {len(sp):3d}, row span mean {np.mean(sp):5.2f} max {max(sp)}")
    sp1 = [max(r for c in rows[p] for r in rows[p][c]) - min(r for c in rows[p] for r in rows[p][c])
           for p in rows if len(rows[p]) == 1]
    tot = sum(32 * s for s in span); 
    print(f"  sum over groups of 32 b x row span = {tot} bit-rows; per cfg pair, the mean span added by mixing two"
          " classes in one register:")
    for a in cls:
        for b in cls:
            if a >= b:
                continue
            sp = []
            for p in rows:
                ra = {r for c in rows[p] if c in cls[a] for r in rows[p][c]}
                rb = {r for c in rows[p] if c in cls[b] for r in rows[p][c]}
                if ra and rb:
                    sp.append(max(ra | rb) - min(ra | rb) - max(max(ra) - min(ra), max(rb) - min(rb)))
            print(f"    {a.split(' (')[0]:12s} + {b.split(' (')[0]:12s}: {len(sp):3d} groups, extra span mean {np.mean(sp):.2f}")


def main():
    print("# R8c S2 demand model (impl/r8c/model.py) [Mod]")
    print("## (1) S2 mechanism")
    mechanism()
    regs, t1, t2 = SR.build()
    s1, s2 = SR.ref()
    print("## (2) networks (32-b group terms)")
    print(f"  a (S1M=1):     S1 regs {len(s1)}  S1 terms {sum(len(s1[p]) for p in s1)}  S2 terms "
          f"{sum(len(s2[u]) for u in s2)}")
    rr = [len({u // TAPS for u in range(144) if r in t2[u]}) for r in regs]
    print(f"  r (S2M=1):     S1 regs {len(regs)}  S1 terms {sum(len(t1[r]) for r in regs)}  S2 terms "
          f"{sum(len(t2[u]) for u in t2)}  (act rows per reg <= {max(rr)}, all within home +- 1)")
    print("## (3) 1-D placement model, y wirelength (bit-m) / cut")
    res = {}
    for v in ("a", "r"):
        wl, cut, wc = place(v)
        res[v] = (wl, cut)
        print(f"  {v}: y WL {wl / 1e6:6.2f} bit-m; cut peak {cut.max():6.0f} mean {cut.mean():6.0f}; "
              + ", ".join(f"{k} {w / 1e6:.2f}" for k, w in sorted(wc.items(), key=lambda t: -t[1])))
    a, r = res["a"], res["r"]
    print(f"  r vs a: WL {100 * (r[0] / a[0] - 1):+.1f} %, peak cut {100 * (r[1].max() / a[1].max() - 1):+.1f} %, "
          f"mean cut {100 * (r[1].mean() / a[1].mean() - 1):+.1f} %")


if __name__ == "__main__":
    main()
