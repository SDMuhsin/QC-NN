#!/usr/bin/env python3
"""R19 (opt-in QB_ACT_S1P on top of QB_ACT_S1M = 1 + QB_ACT_S2M + QB_ACT_RPL, results/r19.md): band-partitioned S1.
Called by gen_act2.py (appends the modules to qb_act2_net.sv, inside `ifdef QB_ACT_S1P); standalone: prints statistics.

Problem (R18): the R8c row-homed S1 (qba2_s1r) reads every lb word from all 16 act rows; the lb flops of every slot are
spread over the whole block and all 16 S1 AND-OR trees land in one middle band -> vertical bisection overflow.
Structure (band map pj = hw/tb/qb_act2_s1p_pj.txt, from impl/r19/s1cut.py):
  * line-buffer word j (32 b; all 8 slots, both contexts, its pre-mux) belongs to act-row band pj[j]; 4 words per band
    and every band holds words of one quarter only (j // 16 = Q(b)), so the R13 region-replicated write enables
    become per band: wer[b][s] = write of slot s and quarter Q(b) (qba2_s1p_bq, qba2_lb_p); same 16 x 8 registers;
  * qba2_s1p_b<b> (one instance per band): the band's 1 024-b pre-mux (select s1c_r[b]; a qba2_pm_r instance, so that
    synthesis keeps it a 2:1 mux instead of folding it into every term: first DC without it +38 % S1 area) and, for every S1 register r
    (gen_act2_s2m.build, home row h) with terms in the band, the partial OR of those terms.  The partials of r are
    OR-ed band by band towards h (cascade: one 32-b net per cut between h and the farthest source band, per side);
    band h ORs its own partial with both incoming chains and holds the s1 register.
  Pure reassociation of the qba2_s1r terms (same terms, same conditions, same register stage): bit- and cycle-exact.
Mutant QBA_MUT_S1P: one term of one partial (a band other than the register's home) is dropped.
    python3 qc18bacc/hw/tb/gen_act2_s1p.py
"""
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_act2_s2m as SR  # noqa: E402

NB, NJ, NSEL1, NCFG = 16, 64, 39, 11
PJ_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qb_act2_s1p_pj.txt")


def load_pj():
    pj = {}
    for ln in open(PJ_FILE):
        if ln.strip() and not ln.startswith("#"):
            j, b = map(int, ln.split())
            pj[j] = b
    assert sorted(pj) == list(range(NJ))
    words = {b: sorted(j for j in range(NJ) if pj[j] == b) for b in range(NB)}
    assert all(len(words[b]) == 4 for b in range(NB)), "4 words per band"
    qb = {}
    for b in range(NB):
        qs = {j // 16 for j in words[b]}
        assert len(qs) == 1, ("band mixes quarters", b, words[b])
        qb[b] = qs.pop()
    return pj, words, qb


def build():
    regs, t1, t2 = SR.build()
    SR.check(regs, t1, t2)
    pj, words, qb = load_pj()
    loc = defaultdict(list)               # (r, b) -> [G]
    span = {}
    for r in regs:
        for G in sorted(t1[r]):
            loc[(r, pj[G % NJ])].append(G)
        bs = {pj[G % NJ] for G in t1[r]} | {r[0]}
        span[r] = (min(bs), max(bs))
    # exactness at term level: every term of r in exactly one band partial
    for r in regs:
        got = sorted(G for b in range(NB) for G in loc.get((r, b), []))
        assert got == sorted(t1[r]), r
    dn = {c: [r for r in regs if r[0] <= c < span[r][1]] for c in range(NB - 1)}   # cut c: band c+1 -> c
    up = {c: [r for r in regs if span[r][0] <= c < r[0]] for c in range(NB - 1)}   # cut c: band c -> c+1
    return regs, t1, pj, words, qb, loc, span, dn, up


def pick_mutant(regs, t1, loc):
    best = None
    for (r, b), Gs in loc.items():
        if b == r[0]:
            continue
        for G in Gs:
            k = (len(t1[r][G]), -r[0], -G)
            if best is None or k > best[0]:
                best = (k, r, b, G)
    return best[1:]


def emit(mut=True):
    regs, t1, pj, words, qb, loc, span, dn, up = build()
    idx = {r: i for i, r in enumerate(regs)}
    mr, mb, mG = pick_mutant(regs, t1, loc)
    L = ["`ifdef QB_ACT_S1P",
         "// R19 (QB_ACT_S1P, see gen_act2_s1p.py): band-partitioned S1.  Band map (word j -> act-row band): "
         + " ".join(f"{j}:{pj[j]}" for j in range(NJ)), ""]
    # quarter of each band (write enables)
    L += ["// quarter of the words of band b: bq[b] = wqm[Q(b)]",
          "module qba2_s1p_bq (",
          "    input  logic [3:0]  wqm,",
          "    output logic [15:0] bq);"]
    for b in range(NB):
        L.append(f"    assign bq[{b}] = wqm[{qb[b]}];")
    L += ["endmodule", ""]
    pjv = sum(pj[j] << (4 * j) for j in range(NJ))
    L += ["// line buffer of one context (as qba2_lb_r) with the write enables per band: wer[b][s] = slot s, words of band b",
          "module qba2_lb_p (",
          "    input  logic            clk,",
          "    input  logic [2:0]      shq,",
          "    input  logic [15:0][7:0] wer,",
          "    input  logic            wzero,",
          "    input  logic            ws,",
          "    input  logic [511:0]    rdq,",
          "    input  logic [2047:0]   sdq,",
          "    output logic [16383:0]  lbf);",
          f"    localparam logic [255:0] PJ = 256'h{pjv:064x};",
          "    logic [2047:0] lb [8];",
          "    logic [2047:0] wd;",
          "    always_comb for (int s = 0; s < 8; s++) lbf[2048 * s +: 2048] = lb[s];",
          "    always_comb wd = wzero ? 2048'd0 : ws ? sdq : {4{rdq}};",
          "    always_ff @(posedge clk) begin",
          "        for (int s = 0; s < 8; s++) begin",
          "            logic [2047:0] nx;",
          "            nx = lb[s];",
          "            if (shq[0] && s + 1 < 8) nx = lb[(s + 1) % 8];",
          "            if (shq[1] && s + 2 < 8) nx = lb[(s + 2) % 8];",
          "            if (shq[2] && s + 4 < 8) nx = lb[(s + 4) % 8];",
          "            for (int j = 0; j < 64; j++)",
          "                if (wer[PJ[4 * j +: 4]][s]) nx[32 * j +: 32] = wd[32 * j +: 32];",
          "            lb[s] <= nx;",
          "        end",
          "    end",
          "endmodule", ""]
    nterm = npart = 0
    for b in range(NB):
        W = words[b]
        din, dout = (dn[b] if b < NB - 1 else []), (dn[b - 1] if b > 0 else [])
        uin, uout = (up[b - 1] if b > 0 else []), (up[b] if b < NB - 1 else [])
        home = [r for r in regs if r[0] == b]
        ports = ["    input  logic                 clk,",
                 f"    input  logic [1023:0]        lb0, lb1,   // words {W} of slots 0..7: bit 128 s + 32 i + k",
                 "    input  logic                 ctx,        // s1c_r[b]",
                 f"    input  logic [{NSEL1 - 1}:0]          sel,",
                 f"    input  logic [{NCFG - 1}:0]          sel2"]
        if din:
            ports.append(f"    input  logic [{32 * len(din) - 1}:0]   dn_i       // from band {b + 1}")
        if uin:
            ports.append(f"    input  logic [{32 * len(uin) - 1}:0]   up_i       // from band {b - 1}")
        if dout:
            ports.append(f"    output logic [{32 * len(dout) - 1}:0]   dn_o       // to band {b - 1}")
        if uout:
            ports.append(f"    output logic [{32 * len(uout) - 1}:0]   up_o       // to band {b + 1}")
        ports.append(f"    output logic [{32 * len(home) - 1}:0]   s1         // registers homed at row {b}")
        L.append(f"// band {b}: pre-mux + partial ORs of words {W} (quarter {qb[b]}), S1 registers of home row {b}")
        L.append(f"module qba2_s1p_b{b} (")
        for k, p in enumerate(ports):
            d, _, cm = p.partition("//")
            d = d.rstrip().rstrip(",") + ("," if k < len(ports) - 1 else "")
            L.append(d + (f"   //{cm}" if cm else ""))
        L.append(");")
        L += ["    logic [1023:0] m;",
              "    qba2_pm_r u_pm (.lb0, .lb1, .ctx, .m);   // R13 pre-mux module: kept as a 2:1 mux by synthesis (hierarchy)"]
        if home:
            L += [f"    logic [{32 * len(home) - 1}:0] s1_d;",
                  "    always_ff @(posedge clk) s1 <= s1_d;"]

        def part(r):
            nonlocal nterm
            ts = []
            for G in loc.get((r, b), []):
                s, j = divmod(G, NJ)
                i = W.index(j)
                t = f"({{32{{{SR.cond1(t1[r][G])}}}}} & m[{128 * s + 32 * i} +: 32])"
                ts.append((G, t))
            nterm += len(ts)
            return ts

        def orl(ts, extra, mutate):
            if mutate:
                keep = [t for G, t in ts if G != mG]
                return " | ".join(keep + extra) if keep + extra else "'0"
            return " | ".join([t for _, t in ts] + extra)

        for k, r in enumerate(dout):
            ts = part(r)
            npart += bool(ts)
            ex = [f"dn_i[{32 * din.index(r)} +: 32]"] if r in din else []
            lhs = f"    assign dn_o[{32 * k} +: 32] ="
            tag = f"   // reg {idx[r]} (home {r[0]}) down"
            if mut and r == mr and b == mb:
                L += ["`ifdef QBA_MUT_S1P", f"{lhs} {orl(ts, ex, True)};{tag} (mutant: term {mG} dropped)", "`else"]
                L += [f"{lhs} {orl(ts, ex, False)};{tag}", "`endif"]
            else:
                L.append(f"{lhs} {orl(ts, ex, False)};{tag}")
        for k, r in enumerate(uout):
            ts = part(r)
            npart += bool(ts)
            ex = [f"up_i[{32 * uin.index(r)} +: 32]"] if r in uin else []
            lhs = f"    assign up_o[{32 * k} +: 32] ="
            tag = f"   // reg {idx[r]} (home {r[0]}) up"
            if mut and r == mr and b == mb:
                L += ["`ifdef QBA_MUT_S1P", f"{lhs} {orl(ts, ex, True)};{tag} (mutant: term {mG} dropped)", "`else"]
                L += [f"{lhs} {orl(ts, ex, False)};{tag}", "`endif"]
            else:
                L.append(f"{lhs} {orl(ts, ex, False)};{tag}")
        for k, r in enumerate(home):
            ts = part(r)
            npart += bool(ts)
            ex = ([f"dn_i[{32 * din.index(r)} +: 32]"] if r in din else []) + \
                 ([f"up_i[{32 * uin.index(r)} +: 32]"] if r in uin else [])
            assert ts or ex, r
            L.append(f"    assign s1_d[{32 * k} +: 32] = {orl(ts, ex, False)};   // reg {idx[r]} (home {b})")
        L += ["endmodule", ""]
    # wrapper
    L += ["// QB_ACT_S1P S1: one qba2_s1p_b<b> per act-row band; s1 in the qba2_s1r register order",
          "module qba2_s1p (",
          "    input  logic          clk,",
          "    input  logic [16383:0] lb0, lb1,",
          "    input  logic [15:0]   ctx,       // s1c_r",
          f"    input  logic [{NSEL1 - 1}:0]   sel1a, sel1b,",
          f"    input  logic [{NCFG - 1}:0]   sel2,",
          f"    output logic [{32 * len(regs) - 1}:0] s1);",
          f"    wire [{NSEL1 - 1}:0] sel = sel1a | sel1b;"]
    for c in range(NB - 1):
        if dn[c]:
            L.append(f"    logic [{32 * len(dn[c]) - 1}:0] dn_{c};   // cut {c}: band {c + 1} -> {c}")
        if up[c]:
            L.append(f"    logic [{32 * len(up[c]) - 1}:0] up_{c};   // cut {c}: band {c} -> {c + 1}")
    for b in range(NB):
        W = words[b]
        L.append(f"    logic [1023:0] w0_{b}, w1_{b};")
        for s in range(8):
            for i, j in enumerate(W):
                L.append(f"    assign w0_{b}[{128 * s + 32 * i} +: 32] = lb0[{2048 * s + 32 * j} +: 32];  "
                         f"assign w1_{b}[{128 * s + 32 * i} +: 32] = lb1[{2048 * s + 32 * j} +: 32];")
        home = [r for r in regs if r[0] == b]
        L.append(f"    logic [{32 * len(home) - 1}:0] s1_{b};")
        for k, r in enumerate(home):
            L.append(f"    assign s1[{32 * idx[r]} +: 32] = s1_{b}[{32 * k} +: 32];")
        con = [".clk", f".lb0(w0_{b})", f".lb1(w1_{b})", f".ctx(ctx[{b}])", ".sel", ".sel2"]
        if b < NB - 1 and dn[b]:
            con.append(f".dn_i(dn_{b})")
        if b > 0 and up[b - 1]:
            con.append(f".up_i(up_{b - 1})")
        if b > 0 and dn[b - 1]:
            con.append(f".dn_o(dn_{b - 1})")
        if b < NB - 1 and up[b]:
            con.append(f".up_o(up_{b})")
        con.append(f".s1(s1_{b})")
        L.append(f"    qba2_s1p_b{b} u_b{b} ({', '.join(con)});")
    L += ["endmodule", "`endif", ""]
    st = dict(nterm=nterm, npart=npart, mut=(idx[mr], mr, mb, mG),
              cut=[32 * (len(dn[c]) + len(up[c])) for c in range(NB - 1)])
    return L, st


def main():
    L, st = emit()
    print(f"S1P: {st['nterm']} terms in {st['npart']} non-empty partials; cascade bits per cut {st['cut']} "
          f"(max {max(st['cut'])}); mutant QBA_MUT_S1P: reg {st['mut'][0]} {st['mut'][1]} band {st['mut'][2]} "
          f"term G {st['mut'][3]}")


if __name__ == "__main__":
    main()
