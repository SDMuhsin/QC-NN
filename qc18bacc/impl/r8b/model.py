#!/usr/bin/env python3
"""R8b: wire-demand model of the act supply's gather networks (qb_act2: line buffers -> S1 -> S2 -> act).
All counts at 32-b group granularity (x 32 for bits).  Variants:
  base   R2b S1 (qba2_s1): flat AND-OR over lb0 and lb1, 39 one-hot lines
  a      context pre-mux per LB bit (M = ctx ? lb1 : lb0), then the same flat AND-OR once
  ab     pre-mux + chunk select as a 4-stage shifter (shift g W in groups: 32 / 16 / 8 / 4), 1x1 / int8 terms flat
Outputs (stdout): (1) connection counts / fan-in / fan-out, (2) source -> destination index span per select class
under the current (chunk-major) bit order, (3) 1-D placement model along the block height (act rows fixed at column 0's
act-pin y, S / map inputs at the south edge, rank spreading by cell area): y wirelength and peak / mean cut demand.
    python3 qc18bacc/impl/r8b/model.py
"""
import os
import sys
from collections import defaultdict

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "hw", "tb"))
import gen_act as GA    # noqa: E402
import gen_act2 as G2   # noqa: E402

S1 = G2.build()
POS = sorted(S1)
_, S2, _ = GA.build()
CLS = [("W32 3x3", range(0, 2)), ("W16 3x3", range(2, 6)), ("W8 3x3", range(6, 14)), ("W4 3x3", range(14, 30)),
       ("1x1 gather", range(30, 33)), ("int8 b6.c1", [33]), ("int8 b6.sc", [34]), ("int8 b6.c2", range(35, 39))]
def cls_of(l):
    return next(n for n, r in CLS if l in r)

# act row y in the block (um): column 0 act-pin y ranges (tau4 col_act_pins.txt, row r = bits 288 r ..) - yoff 690
ROWY = [(a + b) / 2 - 690 for a, b in [(1237.8, 1317.8), (1357, 1437), (1479.8, 1559.8), (1577.4, 1675), (1697.4, 1795),
        (1815.4, 1913), (1934.2, 2031.8), (2053.4, 2151), (2169.4, 2267), (2287.4, 2385), (2406.2, 2503.8),
        (2525.4, 2623), (2638.2, 2735.8), (2755.4, 2853), (2875.4, 2973), (2994.2, 3091.8)]]
H = 2420.0


def s1_edges(var):
    """S1 data edges (src node, dst node) at group level; src nodes ('lb', c, G) / ('m', G) / ('t', k, s, x)."""
    E = []
    if var == "base":
        for p in POS:
            for c in (0, 1):
                for Gg in S1[p]:
                    E.append((("lb", c, Gg), ("s1", p)))
        return E
    for Gg in range(512):                                       # pre-mux
        E += [(("lb", 0, Gg), ("m", Gg)), (("lb", 1, Gg), ("m", Gg))]
    if var == "a":
        for p in POS:
            for Gg in S1[p]:
                E.append((("m", Gg), ("s1", p)))
        return E
    # ab: per slot, 3x3 outputs x < wmax(s) through the shifter, other lines flat
    for s in range(8):
        xs = [x for (ss, x) in POS if ss == s]
        e3 = [x for x in xs if any(l < 30 for Gg, ls in S1[(s, x)].items() for l in ls)]
        if not e3:
            continue
        for x in range(32):
            for sh in (0, 32):
                if x + sh < 64:
                    E.append((("m", 64 * s + x + sh), ("t", 1, s, x)))
        for k, (st, w) in enumerate(((16, 16), (8, 8), (4, 4)), start=2):
            for x in range(w):
                for sh in (0, st):
                    E.append((("t", k - 1, s, x + sh), ("t", k, s, x)))
        for x in e3:
            k = 4 if x < 4 else 3 if x < 8 else 2 if x < 16 else 1
            E.append((("t", k, s, x), ("s1", (s, x))))
    for p in POS:
        for Gg, ls in S1[p].items():
            if any(l >= 30 for l in ls):
                E.append((("m", Gg), ("s1", p)))
    return E


def stats(var):
    E = s1_edges(var)
    fo = defaultdict(int); fi = defaultdict(int)
    for a, b in E:
        fo[a] += 1; fi[b] += 1
    lbfo = [fo[("lb", c, Gg)] for c in (0, 1) for Gg in range(512)]
    s1fi = [fi[("s1", p)] for p in POS]
    mid = sum(1 for a, b in E if b[0] != "s1" and a[0] != "lb") if var == "ab" else 0
    h = lambda v: {k: v.count(k) for k in sorted(set(v))}
    return (f"{var:4s}: S1 data-input connections {32 * len(E):7d} bits ({len(E)} groups); "
            f"LB-bit fan-out mean {np.mean(lbfo):.2f} max {max(lbfo)}; S1-bit fan-in mean {np.mean(s1fi):.2f} max {max(s1fi)}"
            + (f"; shifter-internal {32 * mid} bits" if mid else "") + f"\n      LB fan-out hist {h(lbfo)}")


def spans():
    """(2) index span of every base S1 candidate (per context), by select class: group displacement |G mod 64 - x|,
    slot displacement; and per-LB-group fan-out by class."""
    out = []
    agg = defaultdict(lambda: [0, 0, 0, 0, 0])
    for p in POS:
        for Gg, ls in S1[p].items():
            for l in ls:
                a = agg[cls_of(l)]
                d = abs(Gg % 64 - p[1]); ds = abs(Gg // 64 - p[0])
                a[0] += 1; a[1] += d; a[2] = max(a[2], d); a[3] += ds > 0; a[4] += d * 32
    tot = sum(v[0] for v in agg.values())
    for n, _ in CLS:
        c, sd, mx, xs, bd = agg[n]
        out.append(f"  {n:11s} candidates {c:4d} ({100 * c / tot:4.1f} %)  group span mean {sd / c:5.1f} max {mx:2d}"
                   f"  cross-slot {xs:3d}  sum |span| x 32 b = {bd:6d} bit-groups")
    # distinct (src, dst) pairs: several lines share one AND term
    pairs = sum(len(S1[p]) for p in POS)
    out.append(f"  distinct LB-group -> S1-group pairs per context {pairs} (= AND terms), x 2 contexts x 32 b = {64 * pairs} bit inputs")
    return out


def place(var, iters=150, seed=1, struct=False):
    """(3) 1-D quadratic placement along y with rank spreading; returns y wirelength (bit-um) and the cut profile."""
    rng = np.random.default_rng(seed)
    nodes = {}; fixed = {}
    def node(k, area):
        if k not in nodes:
            nodes[k] = (len(nodes), area)
        return nodes[k][0]
    nets = []          # (list of node idx, bits)
    # act units fixed at their row; S2 terms live at the act unit (r, t)
    for u in range(144):
        i = node(("act", u), 0.0); fixed[i] = ROWY[u // 9]
    # inputs: S read 64 groups + map read 16 groups, pins at the south edge
    for j in range(64):
        pin = node(("pin_s", j), 0.0); fixed[pin] = 0.0
        sq = node(("sdq", j), 32 * 6.5)
        nets.append(([pin, sq], 32, 'S/map in'))
        nets.append(([sq] + [node(("lb", c, 64 * s + j), 440.0) for c in (0, 1) for s in range(8)], 32, 'sdq/rdq -> LB'))
    for i in range(16):
        pin = node(("pin_m", i), 0.0); fixed[pin] = 0.0
        rq = node(("rdq", i), 32 * 6.5)
        nets.append(([pin, rq], 32, 'S/map in'))
        nets.append(([rq] + [node(("lb", c, 64 * s + Gg), 440.0) for c in (0, 1) for s in range(8)
                             for Gg in range(64) if Gg % 16 == i], 32, 'sdq/rdq -> LB'))
    # line-buffer Q nets: shift sinks + S1-network sinks
    E = s1_edges(var)
    sinks = defaultdict(list)
    for a, b in E:
        sinks[a].append(b)
    area = {"m": 32 * 3.6, "t": 32 * 3.6, "s1": (1234.0 if var == "base" else 900.0 if var == "a" else 380.0)}
    for c in (0, 1):
        for s in range(8):
            for j in range(64):
                d = [node(("lb", c, 64 * (s - k) + j), 440.0) for k in (1, 2, 4) if s - k >= 0]
                d += [node(b, area[b[0]]) for b in sinks[("lb", c, 64 * s + j)]]
                nets.append(([node(("lb", c, 64 * s + j), 440.0)] + d, 32, 'LB Q (shift + S1/premux)'))
    for a in list(sinks):
        if a[0] != "lb":
            nets.append(([node(a, area[a[0]])] + [node(b, area[b[0]]) for b in sinks[a]], 32, 'premux out -> S1' if a[0] == 'm' else 'shifter internal'))
    # S2: S1 group -> act units that read it
    rd = defaultdict(set)
    for u in range(144):
        for p in S2[u]:
            rd[p].add(u)
    for p in POS:
        nets.append(([node(("s1", p), area["s1"])] + [nodes[("act", u)][0] for u in sorted(rd[p])], 32, 'S1 -> act (S2)'))
    n = len(nodes)
    A = np.zeros(n); isf = np.zeros(n, bool); y = rng.uniform(0, H, n)
    for k, (i, a) in nodes.items():
        A[i] = a
    for i, v in fixed.items():
        isf[i] = True; y[i] = v
    if struct:     # structured: LB group G (all slots / contexts) fixed at act row G mod 16
        for k, (i, a) in nodes.items():
            if k[0] == "lb":
                isf[i] = True; y[i] = ROWY[(k[2] % 64) % 16]
    mov = np.where(~isf)[0]
    # area of the fixed act pipe / S2 (4 608 b x 3 flops + S2 84 k) occupies the act rows' band
    for it in range(iters):
        acc = np.zeros(n); wsum = np.zeros(n)
        for pins, b, _ in nets:
            c = y[pins].mean()
            w = b / max(1, len(pins) - 1)
            acc[pins] += w * c; wsum[pins] += w
        tgt = np.where(wsum > 0, acc / np.maximum(wsum, 1e-9), y)
        ynew = 0.5 * y + 0.5 * tgt
        o = mov[np.argsort(ynew[mov])]
        cum = np.cumsum(A[o]) - A[o] / 2
        spread = cum / A[o].sum() * H
        y[o] = 0.6 * ynew[o] + 0.4 * spread if it < iters - 1 else spread
    wl = 0.0; wc = defaultdict(float)
    cut = np.zeros(242)                       # 10-um bins
    for pins, b, cl in nets:
        lo, hi = y[pins].min(), y[pins].max()
        wl += b * (hi - lo); wc[cl] += b * (hi - lo)
        cut[int(lo // 10):int(hi // 10) + 1] += b
    return wl, cut, sum(A), wc


def main():
    print("# R8b act-supply gather-network demand model (impl/r8b/model.py) [Mod]")
    print("## (1) S1 connections (data inputs, select lines excluded), per bit = x 32 per group")
    for v in ("base", "a", "ab"):
        print(stats(v))
    print("## (2) base S1 candidates per context by select class, chunk-major LB order (G = g W + x in a slot)")
    for l in spans():
        print(l)
    print("## (3) 1-D placement along the block height (H 2420 um, act rows at column 0's y, S / map pins south)")
    for struct in (False, True):
        print("  placement:", "structured (LB group G at act row G mod 16, rest free)" if struct else "free (all movable)")
        res = {}
        for v in ("base", "a", "ab"):
            wl, cut, ar, wc = place(v, struct=struct)
            res[v] = (wl, cut)
            print(f"  {v:4s}: y wirelength {wl / 1e6:6.2f} bit-m; cut (bits across a horizontal line) peak "
                  f"{cut.max():6.0f} mean {cut.mean():6.0f}; area {ar / 1e6:.3f} mm2; by class: "
                  + ", ".join(f"{k} {w / 1e6:.2f}" for k, w in sorted(wc.items(), key=lambda t: -t[1])))
        b = res["base"]
        for v in ("a", "ab"):
            print(f"    {v} vs base: wirelength {100 * (res[v][0] / b[0] - 1):+.1f} %, peak cut {100 * (res[v][1].max() / b[1].max() - 1):+.1f} %,"
                  f" mean cut {100 * (res[v][1].mean() / b[1].mean() - 1):+.1f} %")


if __name__ == "__main__":
    main()
