#!/usr/bin/env python3
"""Writes hw/rtl/qb_act2_net.sv: the S1 chunk-slice network of qb_act2 (R2b: two qb_act contexts, block 6 from the
stream buffer S).  Same S1 groups / order as gen_act.py (so qba_s2 of qb_act_net.sv is reused unchanged), with
  * two line buffers (one per context): every R2 candidate exists for lb0 (select sel1a) and lb1 (sel1b); a context
    raises its select lines only on its own issue, so the AND-OR is the 2:1 context mux;
  * block-6 S-mode candidates (the int8 words sit at the head of the line-buffer FIFO, slot 0 / 1; compile/layout_s.py):
      line 33  cfg 8  (b6.c1, HQ word (plane, chunk) in slot 0):     S1 (iy, ix)        <- slot 0 group 8 iy + ix
      line 34  cfg 9  (b6.sc, decimated HQ words (plane, 0 / 1)):    S1 (2 oy, 4 t + ox) <- slot t >> 2 group 16 (t & 3) + 4 oy + ox
      line 35+q cfg 10 (b6.c2, Z word (plane, chunk >> 2), q = chunk & 3): S1 (iy, ix) <- slot 0 group 16 q + 4 iy + ix
R8b (opt-in QB_ACT_S1M, results/r8b.md): two more S1 forms of the same function, written to the same file:
  * qba2_pm: per-bit context pre-mux m = ctx ? lb1 : lb0 (the contexts never issue in one cycle; ctx = registered
    is_v[1], valid with sel1a / sel1b), a separate module so that synthesis keeps it next to the line buffers;
  * qba2_s1m (QB_ACT_S1M = 1): the flat AND-OR once over m with sel = sel1a | sel1b (half the fan-in);
  * qba2_s1s (QB_ACT_S1M = 2): 3x3 chunk select (S1 (s, x) <- slot s group g W + x) as a 4-stage shifter by g W
    groups (stages 32 / 16 / 8 / 4, stage k only on the outputs x < 64 / 2^k that need it), gated per position by the
    OR of its 3x3 lines; 1x1 gathers and int8 lines stay flat terms over m.  Mutant QBA2_MUT_S1M: stage 16 takes
    the stage-32 select.
  Both are checked here against qba2_s1 at group level for every select line (assertions).
R8c (opt-in QB_ACT_S2M with QB_ACT_S1M = 1, results/r8c.md): qba2_s1r / qba2_s2r, the row-homed S1 / S2 of
  gen_act2_s2m.py (appended to the same file).
R19 (opt-in QB_ACT_S1P, results/r19.md): qba2_s1p (band-partitioned S1) + qba2_lb_p / qba2_s1p_bq of gen_act2_s1p.py
  (appended inside `ifdef QB_ACT_S1P).
R20 (opt-in QB_ACT_S1T, results/r20.md): qba2_s1t (S1P with band-local selects, 4 pre-mux selects per band, paired
  stops on the long register sides) of gen_act2_s1t.py (appended inside `ifdef QB_ACT_S1T).
    python3 qc18bacc/hw/tb/gen_act2.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_act as GA  # noqa: E402

NSEL1 = 39


def build():
    s1, _, _ = GA.build()
    for iy in range(8):
        for ix in range(8):
            s1[(iy, ix)][8 * iy + ix].add(33)
    for oy in range(4):
        for ox in range(4):
            for t in range(8):
                s1[(2 * oy, 4 * t + ox)][(t >> 2) * 64 + 16 * (t & 3) + 4 * oy + ox].add(34)
    for iy in range(4):
        for ix in range(4):
            for q in range(4):
                s1[(iy, ix)][16 * q + 4 * iy + ix].add(35 + q)
    return s1


LB3 = {32: 0, 16: 2, 8: 6, 4: 14}


def line_shift(l):
    """3x3 line l -> (W, g, shift in groups g W); None for 1x1 / int8 lines."""
    if l >= 30:
        return None
    W = 32 if l < 2 else 16 if l < 6 else 8 if l < 14 else 4
    g = l - LB3[W]
    return W, g, g * W


def gen_s1m(s1, pos):
    S1W = 32 * len(pos)
    L = ["", "// R8b (QB_ACT_S1M): context pre-mux of the two line buffers (per bit; select = registered ctx)",
         "module qba2_pm (",
         "    input  logic [16383:0] lb0, lb1,",
         "    input  logic           ctx,",
         "    output logic [16383:0] m);",
         "    assign m = ctx ? lb1 : lb0;",
         "endmodule", "",
         "// R8b (QB_ACT_S1M = 1): flat S1 AND-OR over the pre-muxed line buffer, sel = sel1a | sel1b",
         "module qba2_s1m (",
         "    input  logic                    clk,",
         "    input  logic [16383:0]          m,",
         f"    input  logic [{NSEL1 - 1}:0]             sel1a, sel1b,",
         f"    output logic [{S1W - 1}:0]          s1);",
         f"    logic [{S1W - 1}:0] s1_d;",
         f"    wire  [{NSEL1 - 1}:0] sel = sel1a | sel1b;",
         "    always_ff @(posedge clk) s1 <= s1_d;"]
    for i, p in enumerate(pos):
        terms = [f"({{32{{{' | '.join(f'sel[{l}]' for l in sorted(ls))}}}}} & m[{32 * G} +: 32])"
                 for G, ls in sorted(s1[p].items())]
        L.append(f"    assign s1_d[{32 * i} +: 32] = {' | '.join(terms)};   // slot {p[0]} x {p[1]}")
    L += ["endmodule", ""]
    return L


def gen_s1s(s1, pos):
    """shifter form; returns RTL lines and the group-level model (for the check)."""
    S1W = 32 * len(pos)
    # shift bits: h[k] (k = 0..3 for stages 32 / 16 / 8 / 4) = OR of the 3x3 lines whose g W has that bit
    hb = {k: sorted(l for l in range(30) if (line_shift(l)[2] >> (5 - k)) & 1) for k in range(4)}
    L = ["// R8b (QB_ACT_S1M = 2): S1 with the 3x3 chunk select as a shifter by g W groups (see gen_act2.py)",
         "module qba2_s1s (",
         "    input  logic                    clk,",
         "    input  logic [16383:0]          m,",
         f"    input  logic [{NSEL1 - 1}:0]             sel1a, sel1b,",
         f"    output logic [{S1W - 1}:0]          s1);",
         f"    logic [{S1W - 1}:0] s1_d;",
         f"    wire  [{NSEL1 - 1}:0] sel = sel1a | sel1b;",
         "    always_ff @(posedge clk) s1 <= s1_d;",
         "    wire [3:0] h;"]
    for k in range(4):
        L.append(f"    assign h[{k}] = {' | '.join(f'sel[{l}]' for l in hb[k])};   // shift by {32 >> k} groups")
    L.append("`ifdef QBA2_MUT_S1M")
    L.append("    wire h16 = h[0];                                               // mutant: stage 16 takes the stage-32 select")
    L.append("`else")
    L.append("    wire h16 = h[1];")
    L.append("`endif")
    hs = ["h[0]", "h16", "h[2]", "h[3]"]
    width = [32, 16, 8, 4]
    model = {}
    for sl in range(8):
        xs3 = sorted(x for (ss, x) in pos if ss == sl and any(l < 30 for ls in s1[(ss, x)].values() for l in ls))
        if not xs3:
            continue
        L.append(f"    logic [1023:0] t1_{sl};  logic [511:0] t2_{sl};  logic [255:0] t3_{sl};  logic [127:0] t4_{sl};")
        b = 2048 * sl
        L.append(f"    assign t1_{sl} = {hs[0]} ? m[{b + 1024} +: 1024] : m[{b} +: 1024];")
        L.append(f"    assign t2_{sl} = {hs[1]} ? t1_{sl}[512 +: 512] : t1_{sl}[0 +: 512];")
        L.append(f"    assign t3_{sl} = {hs[2]} ? t2_{sl}[256 +: 256] : t2_{sl}[0 +: 256];")
        L.append(f"    assign t4_{sl} = {hs[3]} ? t3_{sl}[128 +: 128] : t3_{sl}[0 +: 128];")
    for i, p in enumerate(pos):
        sl, x = p
        terms = []
        l3 = sorted(l for ls in s1[p].values() for l in ls if l < 30)
        if l3:
            k = 4 if x < 4 else 3 if x < 8 else 2 if x < 16 else 1
            terms.append(f"({{32{{{' | '.join(f'sel[{l}]' for l in l3)}}}}} & t{k}_{sl}[{32 * x} +: 32])")
        for G, ls in sorted(s1[p].items()):
            lo = sorted(l for l in ls if l >= 30)
            if lo:
                terms.append(f"({{32{{{' | '.join(f'sel[{l}]' for l in lo)}}}}} & m[{32 * G} +: 32])")
        L.append(f"    assign s1_d[{32 * i} +: 32] = {' | '.join(terms)};   // slot {sl} x {x}")
        model[p] = (l3, {G: [l for l in ls if l >= 30] for G, ls in s1[p].items()})
    L += ["endmodule", ""]
    return L, hb, model


def check_s1s(s1, pos, hb, model):
    """for every one-hot line: the shifter form's source group of every position == qba2_s1's (or both none)."""
    for l in range(NSEL1):
        h = [l in hb[k] for k in range(4)]
        for p in pos:
            sl, x = p
            ref = [G for G, ls in s1[p].items() if l in ls]
            assert len(ref) <= 1, (l, p)
            l3, flat = model[p]
            got = [G for G, lo in flat.items() if l in lo]
            if l in l3:
                k = 4 if x < 4 else 3 if x < 8 else 2 if x < 16 else 1
                off = sum(32 >> j for j in range(k) if h[j])
                assert x + off < 64
                got.append(64 * sl + x + off)
            assert got == ref, (l, p, got, ref)


def main():
    s1 = build()
    pos = sorted(s1)
    assert pos == sorted(GA.build()[0]), "S1 group set changed"
    S1W = 32 * len(pos)
    L = ["// GENERATED by qc18bacc/hw/tb/gen_act2.py -- do not edit.  S1 network of qb_act2 (see gen_act2.py header).",
         "module qba2_s1 (",
         "    input  logic                    clk,",
         "    input  logic [16383:0]          lb0, lb1,   // line buffers of context 0 / 1",
         f"    input  logic [{NSEL1 - 1}:0]             sel1a, sel1b,   // one-hot S1 select of context 0 / 1 (registered)",
         f"    output logic [{S1W - 1}:0]          s1);",
         f"    logic [{S1W - 1}:0] s1_d;",
         "    always_ff @(posedge clk) s1 <= s1_d;"]
    n = []
    for i, p in enumerate(pos):
        terms = []
        for lb, sl in (("lb0", "sel1a"), ("lb1", "sel1b")):
            for G, lines in sorted(s1[p].items()):
                cond = " | ".join(f"{sl}[{l}]" for l in sorted(lines))
                terms.append(f"({{32{{{cond}}}}} & {lb}[{32 * G} +: 32])")
        n.append(len(s1[p]))
        L.append(f"    assign s1_d[{32 * i} +: 32] = {' | '.join(terms)};   // slot {p[0]} x {p[1]}")
    L += ["endmodule", ""]
    L += gen_s1m(s1, pos)
    Ls, hb, model = gen_s1s(s1, pos)
    check_s1s(s1, pos, hb, model)
    L += Ls
    import gen_act2_s2m as SR                       # R8c (QB_ACT_S2M): row-homed S1 / S2, checked in gen_act2_s2m.py
    Lr, nr, nt1, nt2 = SR.emit()
    L += Lr
    import gen_act2_s1p as SP                       # R19 (QB_ACT_S1P): band-partitioned S1, checked in gen_act2_s1p.py
    Lp, sp = SP.emit()
    L += Lp
    import gen_act2_s1t as ST                       # R20 (QB_ACT_S1T): S1P timing variant, checked in gen_act2_s1t.py
    Lt, stt = ST.emit()
    L += Lt
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rtl", "qb_act2_net.sv")
    open(out, "w").write("\n".join(L))
    hist = {k: n.count(k) for k in sorted(set(n))}
    print(f"wrote {os.path.relpath(out)}: S1 {len(pos)} groups; LB candidates per context per bit max {max(n)} "
          f"hist {hist} (x 2 contexts); R8b qba2_pm / qba2_s1m / qba2_s1s (checked vs qba2_s1 for all {NSEL1} lines); R8c qba2_s1r / qba2_s2r: {nr} row-homed S1 regs, {nt1} / {nt2} "
          f"S1 / S2 terms (checked vs qba_s2 o qba2_s1m); R19 qba2_s1p: {sp['nterm']} terms in {sp['npart']} band partials; "
          f"R20 qba2_s1t: {stt['nterm']} terms, {stt['nnets']} inter-band nets")


if __name__ == "__main__":
    main()
