#!/usr/bin/env python3
"""R20 (opt-in QB_ACT_S1T on top of QB_ACT_S1P, results/r20.md): timing variant of the band-partitioned S1.
Called by gen_act2.py (appends the modules to qb_act2_net.sv inside `ifdef QB_ACT_S1T); standalone: prints statistics.

R19's qba2_s1p (same band map, same line buffer qba2_lb_p, same terms / conditions / registers) with three changes:
  * band-local selects: every band module gets its own registered copy of sel = sel1a | sel1b (39 b) and sel2 (11 b)
    (qb_act2.sv, QB_ACT_S1T: selt[b] / sel2t[b], loaded with the next-state values of sel1a | sel1b / sel2), instead of
    one OR + 50-b broadcast over the block height (r19_mc tt: 0.40 ns sel1a Q -> band 14);
  * the context pre-mux select is replicated 4 x per band (s1t_c[4 b + q] selects pre-mux bits 256 q +: 256, a
    qba2_pm_q instance each) instead of one s1c_r[b] per 1 024 bits (r19_mc tt: 0.50 ns s1c_r Q -> pre-mux out);
  * the line-buffer shift select shq (3 b per context) is replicated per band (qb_act2.sv: shqt[b], loaded with shq's
    next-state value; qba2_lb_t: word j shifts with shqt[pj[j]]) instead of one 3-b broadcast to 16 k flops per
    context (r19_mc tt: shq -> lb 13 buffers, 0.50 ns net);
  * the band-to-band OR: per register side (dn = source bands above the home row, up = below), the source bands are
    taken nearest-first; for the sides listed in hw/tb/qb_act2_s1t_grp.txt (impl/r20/s1tree.py) consecutive sources
    are grouped in pairs: the member nearest the home is a stop (ORs its partial, the partner's partial sent express,
    and the chain from the next stop), so the chain has half the OR stages; other sides keep the R19 cascade (every
    source band is a stop).  Inter-band nets are connected in the wrapper (no feed-through ports).
  Pure reassociation of the qba2_s1r terms (checked below: every term in exactly one partial, every partial reaches the
  home register exactly once); same register stage, no extra cycle.
Mutant QBA_MUT_S1T: one term of an express (non-stop) partial is dropped; QBA_MUT_S1TQ (qb_act2.sv): band 3's shift
select copy never shifts.
    python3 qc18bacc/hw/tb/gen_act2_s1t.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_act2_s1p as SP  # noqa: E402
import gen_act2_s2m as SR  # noqa: E402

NB, NJ, NSEL1, NCFG, NPMQ = 16, 64, 39, 11, 4
GRP_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qb_act2_s1t_grp.txt")


def load_grp():
    g = set()
    for ln in open(GRP_FILE):
        if ln.strip() and not ln.startswith("#"):
            i, s = ln.split()
            g.add((int(i), s))
    return g


def build():
    regs, t1, pj, words, qb, loc, span, dn, up = SP.build()
    grp = load_grp()
    idx = {r: i for i, r in enumerate(regs)}
    # signals: key -> (source band, kind); kind 'p' = partial of (r, b) sent express, 'n' = node output of a stop
    outs = {b: [] for b in range(NB)}          # band -> [key]
    ins = {b: [] for b in range(NB)}           # band -> [key]
    node = {}                                  # (r, side, stop band) -> [input keys]  (plus the own partial)
    home_in = {r: [] for r in regs}
    for r in regs:
        h = r[0]
        srcs = sorted({b for (rr, b) in loc if rr == r})
        for side, S in (("dn", sorted(b for b in srcs if b > h)), ("up", sorted((b for b in srcs if b < h), reverse=True))):
            if not S:
                continue
            g = 2 if (idx[r], side) in grp else 1
            stops = [S[i] for i in range(0, len(S), g)]
            for si, st in enumerate(stops):
                inp = []
                for m in S[S.index(st) + 1: S.index(st) + g]:          # partners: express partial -> stop
                    k = ("p", r, m)
                    outs[m].append(k); ins[st].append(k); inp.append(k)
                if si + 1 < len(stops):                                 # chain from the next stop outwards
                    k = ("n", r, side, stops[si + 1])
                    ins[st].append(k); inp.append(k)
                node[(r, side, st)] = inp
                k = ("n", r, side, st)
                outs[st].append(k)
                if si == 0:
                    ins[h].append(k); home_in[r].append(k)
    # exactness: expand every home register into source partials; each (r, b) partial exactly once
    def expand(k):
        if k[0] == "p":
            return [k[2]]
        _, r, side, st = k
        res = [st]
        for x in node[(r, side, st)]:
            res += expand(x)
        return res
    for r in regs:
        got = [r[0]] if (r, r[0]) in loc else []
        for k in home_in[r]:
            got += expand(k)
        want = sorted(b for (rr, b) in loc if rr == r)
        assert sorted(got) == want, (r, got, want)
    for b in range(NB):
        for k in outs[b]:
            if k[0] == "n":
                assert (k[1], k[2], k[3]) in node
    return regs, t1, pj, words, qb, loc, idx, outs, ins, node, home_in, grp


def pick_mutant(regs, t1, loc, outs):
    for b in range(NB):
        for k in outs[b]:
            if k[0] == "p":
                r = k[1]
                Gs = loc[(r, b)]
                return r, b, Gs[0]
    raise AssertionError("no express partial")


def emit(mut=True):
    regs, t1, pj, words, qb, loc, idx, outs, ins, node, home_in, grp = build()
    mr, mb, mG = pick_mutant(regs, t1, loc, outs)
    L = ["`ifdef QB_ACT_S1T",
         "// R20 (QB_ACT_S1T, see gen_act2_s1t.py): qba2_s1p with band-local selects, 4 pre-mux selects per band and paired",
         f"// stops on {len(grp)} register sides (hw/tb/qb_act2_s1t_grp.txt).  Band map and line buffer as QB_ACT_S1P.", "",
         "// a 256-b part of the context pre-mux (as qba2_pm_r)",
         "// line buffer of one context (as qba2_lb_p) with the shift select per band: word j shifts with shq[pj[j]]",
         "module qba2_lb_t (",
         "    input  logic            clk,",
         "    input  logic [15:0][2:0] shq,",
         "    input  logic [15:0][7:0] wer,",
         "    input  logic            wzero,",
         "    input  logic            ws,",
         "    input  logic [511:0]    rdq,",
         "    input  logic [2047:0]   sdq,",
         "    output logic [16383:0]  lbf);",
         f"    localparam logic [255:0] PJ = 256'h{sum(pj[j] << (4 * j) for j in range(NJ)):064x};",
         "    logic [2047:0] lb [8];",
         "    logic [2047:0] wd;",
         "    always_comb for (int s = 0; s < 8; s++) lbf[2048 * s +: 2048] = lb[s];",
         "    always_comb wd = wzero ? 2048'd0 : ws ? sdq : {4{rdq}};",
         "    always_ff @(posedge clk) begin",
         "        for (int s = 0; s < 8; s++) begin",
         "            logic [2047:0] nx;",
         "            for (int j = 0; j < 64; j++) begin",
         "                logic [2:0] q;",
         "                q = shq[PJ[4 * j +: 4]];",
         "                nx[32 * j +: 32] = lb[s][32 * j +: 32];",
         "                if (q[0] && s + 1 < 8) nx[32 * j +: 32] = lb[(s + 1) % 8][32 * j +: 32];",
         "                if (q[1] && s + 2 < 8) nx[32 * j +: 32] = lb[(s + 2) % 8][32 * j +: 32];",
         "                if (q[2] && s + 4 < 8) nx[32 * j +: 32] = lb[(s + 4) % 8][32 * j +: 32];",
         "                if (wer[PJ[4 * j +: 4]][s]) nx[32 * j +: 32] = wd[32 * j +: 32];",
         "            end",
         "            lb[s] <= nx;",
         "        end",
         "    end",
         "endmodule", "",
         "module qba2_pm_q (",
         "    input  logic [255:0] lb0, lb1,",
         "    input  logic         ctx,",
         "    output logic [255:0] m);",
         "    assign m = ctx ? lb1 : lb0;",
         "endmodule", ""]
    nterm = 0
    kname = {}
    for b in range(NB):
        W = words[b]
        home = [r for r in regs if r[0] == b]
        no, ni = len(outs[b]), len(ins[b])
        ports = ["    input  logic                 clk,",
                 f"    input  logic [1023:0]        lb0, lb1,   // words {W} of slots 0..7: bit 128 s + 32 i + k",
                 f"    input  logic [{NPMQ - 1}:0]           ctx,        // s1t_c[{NPMQ} b +: {NPMQ}]: pre-mux bits 256 q +: 256",
                 f"    input  logic [{NSEL1 - 1}:0]          sel,        // band copy of sel1a | sel1b",
                 f"    input  logic [{NCFG - 1}:0]          sel2"]
        if ni:
            ports.append(f"    input  logic [{32 * ni - 1}:0]   xi")
        if no:
            ports.append(f"    output logic [{32 * no - 1}:0]   xo")
        if home:
            ports.append(f"    output logic [{32 * len(home) - 1}:0]   s1         // registers homed at row {b}")
        L.append(f"// band {b}: pre-mux + partial ORs of words {W}; {no} outputs, {ni} inputs; S1 registers of home row {b}")
        L.append(f"module qba2_s1t_b{b} (")
        for k, p in enumerate(ports):
            d, _, cm = p.partition("//")
            d = d.rstrip().rstrip(",") + ("," if k < len(ports) - 1 else "")
            L.append(d + (f"   //{cm}" if cm else ""))
        L.append(");")
        L.append("    logic [1023:0] m;")
        for q in range(NPMQ):
            L.append(f"    qba2_pm_q u_pm{q} (.lb0(lb0[{256 * q} +: 256]), .lb1(lb1[{256 * q} +: 256]), .ctx(ctx[{q}]), "
                     f".m(m[{256 * q} +: 256]));")
        if home:
            L += [f"    logic [{32 * len(home) - 1}:0] s1_d;", "    always_ff @(posedge clk) s1 <= s1_d;"]

        def part(r, mutate=False):
            nonlocal nterm
            ts = []
            for G in loc.get((r, b), []):
                if mutate and G == mG:
                    continue
                s, j = divmod(G, NJ)
                i = W.index(j)
                ts.append(f"({{32{{{SR.cond1(t1[r][G])}}}}} & m[{128 * s + 32 * i} +: 32])")
            if not mutate:
                nterm += len(ts)
            return ts

        def xin(k):
            return f"xi[{32 * ins[b].index(k)} +: 32]"
        for oi, k in enumerate(outs[b]):
            lhs = f"    assign xo[{32 * oi} +: 32] ="
            r = k[1]
            if k[0] == "p":
                tag = f"   // reg {idx[r]} (home {r[0]}) partial, express"
                if mut and r == mr and b == mb:
                    L += ["`ifdef QBA_MUT_S1T", f"{lhs} {' | '.join(part(r, True)) or chr(39) + '0'};{tag} (mutant: term {mG} dropped)",
                          "`else", f"{lhs} {' | '.join(part(r))};{tag}", "`endif"]
                else:
                    L.append(f"{lhs} {' | '.join(part(r))};{tag}")
            else:
                _, r, side, st = k
                ex = [xin(x) for x in node[(r, side, st)]]
                L.append(f"{lhs} {' | '.join(part(r) + ex)};   // reg {idx[r]} (home {r[0]}) {side} stop")
        for hk, r in enumerate(home):
            ts = part(r) if (r, b) in loc else []
            ex = [xin(x) for x in home_in[r]]
            assert ts or ex, r
            L.append(f"    assign s1_d[{32 * hk} +: 32] = {' | '.join(ts + ex)};   // reg {idx[r]} (home {b})")
        L += ["endmodule", ""]
    # wrapper
    L += ["// QB_ACT_S1T S1: one qba2_s1t_b<b> per act-row band; s1 in the qba2_s1r register order",
          "module qba2_s1t (",
          "    input  logic                 clk,",
          "    input  logic [16383:0]       lb0, lb1,",
          f"    input  logic [{NPMQ * NB - 1}:0]          ctx,       // s1t_c",
          f"    input  logic [{NB - 1}:0][{NSEL1 - 1}:0]   sel,       // selt (band copies of sel1a | sel1b)",
          f"    input  logic [{NB - 1}:0][{NCFG - 1}:0]   sel2,      // sel2t",
          f"    output logic [{32 * len(regs) - 1}:0] s1);"]
    nets = []
    for b in range(NB):
        for k in outs[b]:
            nets.append(k)
    nid = {k: i for i, k in enumerate(nets)}
    L.append(f"    logic [{32 * len(nets) - 1}:0] x;   // inter-band nets: {len(nets)} x 32 b")
    for b in range(NB):
        W = words[b]
        L.append(f"    logic [1023:0] w0_{b}, w1_{b};")
        for s in range(8):
            for i, j in enumerate(W):
                L.append(f"    assign w0_{b}[{128 * s + 32 * i} +: 32] = lb0[{2048 * s + 32 * j} +: 32];  "
                         f"assign w1_{b}[{128 * s + 32 * i} +: 32] = lb1[{2048 * s + 32 * j} +: 32];")
        home = [r for r in regs if r[0] == b]
        con = [".clk", f".lb0(w0_{b})", f".lb1(w1_{b})", f".ctx(ctx[{NPMQ * b} +: {NPMQ}])", f".sel(sel[{b}])", f".sel2(sel2[{b}])"]
        if ins[b]:
            L.append(f"    wire [{32 * len(ins[b]) - 1}:0] xi_{b} = {{" + ", ".join(f"x[{32 * nid[k]} +: 32]" for k in reversed(ins[b])) + "};")
            con.append(f".xi(xi_{b})")
        if outs[b]:
            L.append(f"    wire [{32 * len(outs[b]) - 1}:0] xo_{b};")
            for oi, k in enumerate(outs[b]):
                L.append(f"    assign x[{32 * nid[k]} +: 32] = xo_{b}[{32 * oi} +: 32];")
            con.append(f".xo(xo_{b})")
        if home:
            L.append(f"    logic [{32 * len(home) - 1}:0] s1_{b};")
            for k, r in enumerate(home):
                L.append(f"    assign s1[{32 * idx[r]} +: 32] = s1_{b}[{32 * k} +: 32];")
            con.append(f".s1(s1_{b})")
        L.append(f"    qba2_s1t_b{b} u_b{b} ({', '.join(con)});")
    L += ["endmodule", "`endif", ""]
    # stats: per-cut 32-b nets
    cut = [0] * (NB - 1)
    for b in range(NB):
        for k in outs[b]:
            if k[0] == "p":
                r, dst = k[1], None
                for st_b in range(NB):
                    if k in ins[st_b]:
                        dst = st_b
            else:
                r = k[1]
                dst = next(x for x in range(NB) if k in ins[x])
            for c in range(min(b, dst), max(b, dst)):
                cut[c] += 32
    nst = max(sum(1 for (rr, sd, st) in node if rr == r and sd == side) for r in regs for side in ("dn", "up"))
    st = dict(nterm=nterm, nnets=len(nets), cut=cut, mut=(idx[mr], mr, mb, mG), grp=len(grp), maxstops=nst)
    return L, st


def main():
    L, st = emit()
    print(f"S1T: {st['nterm']} terms, {st['nnets']} inter-band 32-b nets, {st['grp']} grouped sides, max stops per side "
          f"{st['maxstops']}; bits per cut {st['cut']} (max {max(st['cut'])}); mutant QBA_MUT_S1T: reg {st['mut'][0]} "
          f"{st['mut'][1]} band {st['mut'][2]} term G {st['mut'][3]}")


if __name__ == "__main__":
    main()
