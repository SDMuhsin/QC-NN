#!/usr/bin/env python3
"""R8c (opt-in QB_ACT_S2M on top of QB_ACT_S1M = 1, results/r8c.md): row-homed S1 / S2 of qb_act2.
Called by gen_act2.py (appends qba2_s1r / qba2_s2r to qb_act2_net.sv); standalone: prints the statistics.

Problem (R8b): the R2 S1 register (slot, x) is shared by all configurations, but its act consumers are at different
rows per configuration: stride 1 (cfg 0 / 1 / 4 / 7 / 10) row ~ x (mod 16 / 8 / 4, several output rows for W <= 8),
stride 2 (cfg 2 / 5 / 8) row x / 2, 1x1 gathers (cfg 3 / 6 / 9) row x mod 16 / 8 / 4.  So most S1 groups feed act rows
spread over the block height (S2 = pixel-to-row network, the top vertical GRT class).
Fix: the S1 register file is re-indexed by act row.  Every (cfg c, S1 value p) of the R2 network is split into clusters
of act rows that span <= 3 rows, and each cluster gets its own register homed at a row h with all its rows in
h - 1 .. h + 1.  Registers are 8 per home row (128 instead of 192; cfg 9 needs 8 per row) and are re-used across
configurations; the S1 select becomes configuration-qualified (term condition = OR of sel2[c] & sel[l], sel2 = the
registered cfg one-hot of the same item, reduced to sel[l] when every configuration that can raise line l agrees).
S2 then only connects a register to act units within +- 1 row of its home.  Bit- and cycle-exact: same registers
in the pipeline (S1 -> act), act(u) as a function of (m, sel, cfg) is checked here against the R2 composition
qba_s2(qba2_s1m) for every reachable (cfg, line) pair (RL below; the RTL flags any other pair in simulation).
Mutant QBA2_MUT_S2M: cfg 4, act row 5 unit 4 reads the register of unit 3.
    python3 qc18bacc/hw/tb/gen_act2_s2m.py
"""
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_act as GA    # noqa: E402
import gen_act2 as G2   # noqa: E402

NCFG, ROWS, TAPS, NSEL1, PER = 11, 16, 9, 39, 8
NEWP = 6.0                                 # score cost of opening a register
# select lines a configuration can raise (qba2_ctx is_sel1: 3x3 by W class, 1x1 30 / 31, int8 33 / 34 / 35 + q)
RL = {0: range(0, 2), 1: range(0, 2), 2: range(0, 2), 3: [30], 4: range(2, 6), 5: range(2, 6), 6: [31],
      7: range(6, 14), 8: [33], 9: [34], 10: list(range(14, 30)) + list(range(35, 39))}
ORDER = [0, 1, 4, 7, 10, 2, 5, 8, 3, 6, 9]


def ref():
    s1 = G2.build()
    _, s2, _ = GA.build()
    return s1, s2


def build():
    s1, s2 = ref()
    # items: (c, p, rows, units) = cluster of act rows of S1 value p under cfg c
    rd = defaultdict(lambda: defaultdict(set))
    for u in range(ROWS * TAPS):
        for p, cs in s2[u].items():
            for c in cs:
                rd[c][p].add(u)
    items = []
    for c in ORDER:
        for p in sorted(rd[c]):
            us = sorted(rd[c][p], key=lambda u: u // TAPS)
            cl = []
            for u in us:
                if cl and u // TAPS - cl[-1][0] // TAPS <= 2:
                    cl[-1].append(u)
                else:
                    cl.append([u])
            for k in cl:
                items.append((c, p, k))
    # greedy assignment: register (h, j), at most one item per (register, cfg)
    used = defaultdict(set)                    # reg -> cfgs
    t1 = defaultdict(lambda: defaultdict(set))  # reg -> G -> {(c, l)}
    t2 = defaultdict(lambda: defaultdict(set))  # u -> reg -> {c}
    load = defaultdict(int)
    # order: items with the fewest home options first within a cfg (keeps the 8 / row packing feasible)
    for c in ORDER:
        its = [it for it in items if it[0] == c]
        for _, p, us in sorted(its, key=lambda it: (max(u // TAPS for u in it[2]) - min(u // TAPS for u in it[2])),
                               reverse=True):
            rows = [u // TAPS for u in us]
            hs = [h for h in range(ROWS) if max(rows) - 1 <= h <= min(rows) + 1]
            src = {G: {(c, l) for l in ls if l in RL[c]} for G, ls in s1[p].items()}
            src = {G: v for G, v in src.items() if v}
            best = None
            for h in hs:
                for j in range(PER + 8):
                    r = (h, j)
                    if c in used[r]:
                        continue
                    ctr = (max(rows) + min(rows)) / 2
                    sc = sum(1 for G in src if G in t1[r]) * 4 + sum(1 for u in us if r in t2[u]) * 2 \
                        - (0 if used[r] else NEWP) - abs(h - ctr) * 0.5 - 0.01 * j
                    if best is None or sc > best[0]:
                        best = (sc, r)
            assert best is not None, ("no register", c, p, rows)
            r = best[1]
            used[r].add(c)
            load[r[0]] += 1
            for G, v in src.items():
                t1[r][G] |= v
            for u in us:
                t2[u][r].add(c)
    regs = sorted(r for r in used if used[r])
    return regs, t1, t2


def cond1(pairs):
    """S1 term condition: sel[l] when every cfg that can raise l is in the set, else sel2[c] & sel[l]."""
    byl = defaultdict(set)
    for c, l in pairs:
        byl[l].add(c)
    out = []
    for l in sorted(byl):
        full = {c for c in range(NCFG) if l in RL[c]}
        if byl[l] == full:
            out.append(f"sel[{l}]")
        else:
            cs = sorted(byl[l])
            out.append(f"(sel[{l}] & ({' | '.join(f'sel2[{c}]' for c in cs)}))" if len(cs) > 1
                       else f"(sel[{l}] & sel2[{cs[0]}])")
    return " | ".join(out)          # fires exactly for the pairs given (a full line = all cfgs that can raise it)


def check(regs, t1, t2):
    """act(u) under (cfg c, line l) = set of LB groups ORed in, new vs R2 composition, for every reachable pair."""
    s1, s2 = ref()
    for c in range(NCFG):
        for l in RL[c]:
            for u in range(ROWS * TAPS):
                want = set()
                for p, cs in s2[u].items():
                    if c in cs:
                        want |= {G for G, ls in s1[p].items() if l in ls}
                got = set()
                for r, cs in t2[u].items():
                    if c in cs:
                        got |= {G for G, pr in t1[r].items() if (c, l) in pr}
                assert got == want, (c, l, u, sorted(got), sorted(want))


def emit(mut=True):
    regs, t1, t2 = build()
    check(regs, t1, t2)
    idx = {r: i for i, r in enumerate(regs)}
    NR = len(regs)
    rlmask = [sum(1 << l for l in RL[c]) for c in range(NCFG)]
    L = ["// R8c (QB_ACT_S2M, see gen_act2_s2m.py): row-homed S1 (register h * 8 + j homed at act row h, cfg-qualified",
         "// select) and S2 (register -> act units of rows h - 1 .. h + 1 only)",
         "module qba2_s1r (",
         "    input  logic                    clk,",
         "    input  logic [16383:0]          m,",
         f"    input  logic [{NSEL1 - 1}:0]             sel1a, sel1b,",
         f"    input  logic [{NCFG - 1}:0]             sel2,    // registered cfg one-hot of the item in sel1a / sel1b",
         f"    output logic [{32 * NR - 1}:0]          s1);",
         f"    logic [{32 * NR - 1}:0] s1_d;",
         f"    wire  [{NSEL1 - 1}:0] sel = sel1a | sel1b;",
         "    always_ff @(posedge clk) s1 <= s1_d;",
         "`ifndef SYNTHESIS",
         "    // the row-homed terms are exact for the (cfg, line) pairs qba2_ctx can raise (gen_act2_s2m.py RL)",
         f"    logic [{NSEL1 - 1}:0] rl;",
         "    always_comb begin",
         "        rl = '0;",
         f"        for (int c = 0; c < {NCFG}; c++) if (sel2[c]) case (c)"]
    for c in range(NCFG):
        L.append(f"            {c}: rl = rl | {NSEL1}'h{rlmask[c]:x};")
    L += ["            default: ;",
          "        endcase",
          "    end",
          "    always_ff @(posedge clk) if (|(sel & ~rl)) $error(\"QBA2_S2M_ERR sel %h cfg %h\", sel, sel2);",
          "`endif"]
    nt1 = 0
    for r in regs:
        terms = []
        for G, pr in sorted(t1[r].items()):
            terms.append(f"({{32{{{cond1(pr)}}}}} & m[{32 * G} +: 32])")
        nt1 += len(terms)
        L.append(f"    assign s1_d[{32 * idx[r]} +: 32] = {' | '.join(terms)};   // home row {r[0]} reg {r[1]}")
    L += ["endmodule", "",
          "module qba2_s2r (",
          "    input  logic                    clk,",
          f"    input  logic [{32 * NR - 1}:0]          s1,",
          f"    input  logic [{NCFG - 1}:0]             sel2,   // one-hot cfg (registered)",
          "    output logic [4607:0]           act);   // row r: bits 288 r + 32 t + k",
          "    logic [4607:0] act_d;",
          "    always_ff @(posedge clk) act <= act_d;"]
    nt2 = 0
    for u in range(ROWS * TAPS):
        terms = []
        for r, cs in sorted(t2[u].items()):
            assert abs(r[0] - u // TAPS) <= 1
            src = idx[r]
            cs = sorted(cs)
            if mut and u == 5 * TAPS + 4 and 4 in cs:
                # mutant: cfg 4 reads the register unit 3 reads
                alt = next(rr for rr, cc in t2[u - 1].items() if 4 in cc)
                L.append("`ifdef QBA2_MUT_S2M")
                cs_m = [c for c in cs if c != 4]
                mt = []
                if cs_m:
                    mt.append(f"({{32{{{' | '.join(f'sel2[{c}]' for c in cs_m)}}}}} & s1[{32 * src} +: 32])")
                mt.append(f"({{32{{sel2[4]}}}} & s1[{32 * idx[alt]} +: 32])")
                others = [f"({{32{{{' | '.join(f'sel2[{c}]' for c in sorted(cc))}}}}} & s1[{32 * idx[rr]} +: 32])"
                          for rr, cc in sorted(t2[u].items()) if rr != r]
                L.append(f"    assign act_d[{32 * u} +: 32] = {' | '.join(mt + others)};")
                L.append("`else")
            terms.append(f"({{32{{{' | '.join(f'sel2[{c}]' for c in cs)}}}}} & s1[{32 * src} +: 32])")
        nt2 += len(terms)
        line = (f"    assign act_d[{32 * u} +: 32] = {' | '.join(terms) if terms else chr(39) + '0'};"
                f"   // row {u // TAPS} unit {u % TAPS}")
        if mut and u == 5 * TAPS + 4:
            L += [line, "`endif"]
        else:
            L.append(line)
    L += ["endmodule", ""]
    return L, NR, nt1, nt2


def stats():
    s1, s2 = ref()
    regs, t1, t2 = build()
    check(regs, t1, t2)
    n1 = sum(len(t1[r]) for r in regs)
    n2 = sum(len(t2[u]) for u in t2)
    o1 = sum(len(s1[p]) for p in s1)
    o2 = sum(len(s2[u]) for u in s2)
    fi1 = [len(t1[r]) for r in regs]
    fi2 = [len(t2[u]) for u in range(ROWS * TAPS)]
    print(f"R2 (S1M=1): S1 regs {len(s1)} terms {o1}; S2 terms {o2}")
    print(f"R8c row-homed: S1 regs {len(regs)} terms {n1} (fan-in max {max(fi1)} mean {n1 / len(regs):.2f}); "
          f"S2 terms {n2} (fan-in max {max(fi2)} mean {n2 / len(fi2):.2f}); check vs R2 composition OK")


if __name__ == "__main__":
    stats()
