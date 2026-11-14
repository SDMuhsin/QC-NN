// qb_seq_rt: R4b retimed qb_seq (hw/rtl/qb_seq.sv, DSCM = 1 semantics).  Same ports, same program, same cycle
// behaviour (qb_top QB_SEQ_RT = 1; in simulation qb_top runs the R3b qb_seq in lockstep and flags any output
// difference).  The R4 critical chains (results/r4.md: load permission 170 MHz, token 239 MHz, end phase 277 MHz) are
// cut by precomputing next-cycle values from registered state:
//   * stamp table writes are registered (cm_v / cm_k / cm_de = the commit of the previous cycle; lookups see table +
//     that pending write, i.e. all commits up to the previous cycle, as the R3b table);
//   * end port: a 4-entry prefetch shift FIFO along the sequential commit chain (0, 1, .., nt - 1, 0, ..) -> the
//     end-phase descriptor e is a register (R3b: macro Q).  rw (drain-time RAW) of the next head is looked up one
//     cycle ahead (head or 2nd entry, by the commit), the commit of the current cycle is bypassed at use (cm_de + rdl,
//     exact); ds / de = max of 4 by parallel compares; ke < nt registered;
//   * tile token: the head's RAW readiness (dep_ok && now >= ra, and now >= ra + OVH) is registered one cycle ahead.
//     Exact because a dependency committed in the previous cycle can never be ready: drained / PPU producers have
//     de >= commit + 4; pecmp producers have de = ce and every RAW latency of the program is >= 11 (asserted in
//     simulation: a pecmp commit is never >= 9 cycles behind its ce).  now + C (C = static items or, block 6,
//     popcount of the writer-side flags, registered) is precomputed; the same-cycle commit of the predecessor tile
//     enters as parallel compares (de <= now + C  <=>  ce, t_sh, lane, rw <= now + C - drain); both outcomes (commit /
//     no commit of an array tile in this cycle) are evaluated in parallel and selected by p_arr (start FIFO = shift
//     FIFO, its head and 2nd entry are registers; now + 1 is a local counter; x + d <= now + 1 compares the table
//     output against now + 1 - d);
//   * load permissions: per context a 3-entry window of the table (lt[lptr .. lptr + 2], registers), the readiness of
//     the next window and its positions (binary: static, int8: (j - lb + 1) x executed S words, from registered
//     popcounts) precomputed; the next pass's first entries prefetched (one lt read per cycle; passes of a context
//     are >= 6 cycles apart, asserted).  l_ok = a few gates after the loader position compare.
// Flags (fs_*) feed popcounts through a register: exact as long as the flags of a block-6 source are final 2
// cycles before they are used (checked in simulation by the lockstep reference: any stale use changes tgo / l_ok).
// LSW (default 16 = R3b): width of the stored load-permission age (l_seq); the s0 / s1 programs use < 1024.
module qb_seq_rt #(parameter int NT = 1024, parameter int OVH = 12, parameter int NLT = 1024, parameter int NDM = 624,
                   parameter int LSW = 16) (
    input  logic         clk, rst_n, go, run,
    input  logic [15:0]  now,
    input  logic         h_we,
    input  logic [3:0]   h_sel,
    input  logic [9:0]   h_addr,
    input  logic [95:0]  h_d,
    input  logic [95:0]  pt [32],
    input  logic [1:0]   done,
    output logic [1:0]   p_fire,
    output logic [4:0]   p_pi [2],
    output logic [1:0]   tgo,
    input  logic [9:0]   l_pos0, l_pos1,
    input  logic [2:0]   fl_quiet,
    output logic [1:0]   l_ok,
    output logic [15:0]  l_seq0, l_seq1,
    input  logic         d_vld, d_eot,
    input  logic [63:0]  fs_hq,
    input  logic [7:0]   fs_hqd,
    input  logic [127:0] fs_z,
    output logic         c_fire, c_cmp,
    output logic [4:0]   c_pi,
    output logic [6:0]   c_tp,
    output logic [3:0]   c_ct,
    output logic         f_fire,
    output logic [15:0]  f_job,
    output logic         w_fire,
    output logic [15:0]  w_job,
    output logic         err
);
    localparam int LTW = 26 + LSW;
    // ---------------------------------------------------------------- program memories
    logic [LTW-1:0] lt [NLT];
    logic [4:0]  pq [2][32];
    logic [5:0]  n_pq [2];
    logic [9:0]  nt, ks0;
    wire wh  = h_we && h_sel == 4'd11;                                  // descriptors (both macros)
    wire wk0 = h_we && h_sel == 4'd15 && h_addr[3:0] == 4'd6;
    wire wnt = h_we && h_sel == 4'd15 && h_addr[3:0] == 4'd7;
    wire wpg = h_we && (h_sel == 4'd4 || h_sel == 4'd5 || h_sel == 4'd10 || (h_sel == 4'd15 && h_addr[3:0] <= 4'd1));
    always_ff @(posedge clk)
        if (h_we) unique case (h_sel)
            4'd4:  pq[0][h_addr[4:0]] <= h_d[4:0];
            4'd5:  pq[1][h_addr[4:0]] <= h_d[4:0];
            4'd10: lt[h_addr] <= h_d[LTW-1:0];
            4'd15: unique case (h_addr[3:0])
                       4'd0: n_pq[0] <= h_d[5:0];
                       4'd1: n_pq[1] <= h_d[5:0];
                       4'd6: ks0 <= h_d[9:0];
                       4'd7: nt <= h_d[9:0];
                       default: ;
                   endcase
            default: ;
        endcase
`ifndef SYNTHESIS
    always @(posedge clk) if (h_we && h_sel == 4'd10 && LSW < 16 && (h_d[41:26] >> LSW) != 16'd0)
        $error("qb_seq_rt: load-permission age %0d does not fit LSW = %0d", h_d[41:26], LSW);
`endif
    typedef struct packed {
        logic       nxv;  logic [9:0] nxa;
        logic [4:0] rdl;  logic [9:0] rdk;  logic rdv;
        logic [4:0] ral;  logic [9:0] rak;  logic rav;
        logic [1:0] i8;   logic [5:0] C;
        logic first, hm, bc2, ctx;  logic [1:0] u;  logic arr;
        logic [3:0] ct;   logic [6:0] tp;  logic [4:0] pi;
    } dsc_t;
    function automatic dsc_t dget(input logic [79:0] w); return dsc_t'(w[73:0]); endfunction
    function automatic logic [15:0] mx(input logic [15:0] a, b); return a > b ? a : b; endfunction

    // ---------------------------------------------------------------- stamp table, registered write
    logic [15:0]   stb [NT];
    logic [NT-1:0] svb;
    logic          cm_v;  logic [9:0] cm_k;  logic [15:0] cm_de;
    function automatic logic [15:0] lst(input logic [9:0] k); return (cm_v && k == cm_k) ? cm_de : stb[k]; endfunction
    function automatic logic        lsv(input logic [9:0] k); return svb[k] || (cm_v && k == cm_k); endfunction
    // npr = now of the next cycle unless go (local copy of qb_top's run / now: npr = run ? now + 1 : now)
    logic [15:0] npr;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) npr <= 16'd0; else if (go) npr <= 16'd1; else if (run) npr <= npr + 16'd1;
    wire [15:0] nowp = go ? 16'd0 : npr;                                // now of the next cycle
    // x + d <= npr, as a compare of the table output against npr - d (the subtraction runs beside the table read);
    // callers force not-ready under go (the valid bits are cleared at go)
    function automatic logic le_n(input logic [15:0] x, input logic [5:0] d);
        return $signed({2'b0, x}) <= $signed({2'b0, npr}) - $signed({12'd0, d});
    endfunction

    // ---------------------------------------------------------------- engine state
    logic [9:0]  ke, ks, kprev;
    logic        ksv, kpv, ce_p, last_v, lbc2;
    logic [15:0] ce_q, t_arr, t_sh, lane_f, lane_w;
    logic [4:0]  last_pi;
    logic        cp_v;  logic [15:0] cp_t;  logic cp_cmp;  logic [4:0] cp_pi;  logic [6:0] cp_tp;  logic [3:0] cp_ct;
    localparam int FD = 32, WD = 8;
    logic [31:0] fq [FD];  logic [5:0] fq_w, fq_r;
    logic [31:0] wq [WD];  logic [3:0] wq_w, wq_r;
    logic        p_arr, p_ppu, s_fire;
    wire         e_pop = p_arr || p_ppu;

    // ---------------------------------------------------------------- descriptor ports (2 macros, as R4 DSCM = 1)
    localparam int DAW = $clog2(NDM);
    localparam int FQD = 4;
    // end port: sequential prefetch FIFO, head = dsc[ke]
    logic [79:0] eqf [FQD];  logic [79:0] qe;                            // shift FIFO: eqf[0] = head
    logic [2:0]  ec;  logic einf, epv;  logic [9:0] ea;
    wire         e_iss = epv && !wh && (32'(ec) + 32'(einf) < FQD);
    qbt_rfsp #(80, NDM) u_de (.clk, .ren(e_iss), .we(wh), .a(wh ? DAW'(h_addr) : DAW'(ea)), .wd(h_d[79:0]), .q(qe));
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin ec <= '0; einf <= 1'b0; epv <= 1'b0; ea <= '0; end
        else if (wh || wnt) begin ec <= '0; einf <= 1'b0; epv <= 1'b1; ea <= '0; end
        else begin
            einf <= e_iss;
            for (int i = 0; i < FQD; i++)
                if (einf && i == int'(ec) - int'(e_pop)) eqf[i] <= qe;
                else if (e_pop && i + 1 < FQD) eqf[i] <= eqf[(i + 1) % FQD];
            if (e_iss) ea <= (ea + 10'd1 >= nt) ? 10'd0 : ea + 10'd1;
            ec <= ec + 3'(einf) - 3'(e_pop);
        end
    dsc_t e, e2;
    assign e  = dget(eqf[0]);
    assign e2 = dget(eqf[1]);
    // start port: prefetch FIFO along the static token chain (R4 DSCM = 1, unchanged)
    logic [79:0] sqf [FQD];  logic [79:0] qs;                            // shift FIFO: sqf[0] = head
    logic [2:0]  fc;  logic inf, pv;  logic [9:0] fa;
    wire  [9:0]  na = inf ? (qs[73] ? qs[72:63] : ks0) : fa;
    wire         issue = pv && !wh && !wk0 && (32'(fc) + 32'(inf) < FQD);
    qbt_rfsp #(80, NDM) u_ds (.clk, .ren(issue), .we(wh), .a(wh ? DAW'(h_addr) : DAW'(na)), .wd(h_d[79:0]), .q(qs));
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin fc <= '0; inf <= 1'b0; pv <= 1'b0; fa <= '0; end
        else if (wh || wk0) begin
            fc <= '0; inf <= 1'b0; pv <= 1'b1; fa <= wk0 ? h_d[9:0] : ks0;
        end else begin
            inf <= issue;
            for (int i = 0; i < FQD; i++)
                if (inf && i == int'(fc) - int'(s_fire)) sqf[i] <= qs;
                else if (s_fire && i + 1 < FQD) sqf[i] <= sqf[(i + 1) % FQD];
            if (!issue) fa <= na;
            fc <= fc + 3'(inf) - 3'(s_fire);
        end
    dsc_t a, a2;
    assign a  = dget(sqf[0]);
    assign a2 = dget(sqf[1]);

    // ---------------------------------------------------------------- one-cycle-ahead lookups (registered)
    // drain-time RAW value of the next end head: commits up to this cycle - 1 (the commit of this cycle is bypassed at
    // use); RAW readiness of the next token head (see the header for exactness).
    logic [15:0] rwH, raH;  logic rok, rokO;
    logic [7:0]  pc_hq, pc_hqd, pc_z;
    logic [17:0] NC, NC4, NC32;                                          // now + C, now + C - 4, now + C - 32 (head)
    function automatic logic [7:0] cnof(input dsc_t x);
        unique case (x.i8)
            2'd1: return pc_hq;
            2'd2: return pc_hqd;
            2'd3: return pc_z;
            default: return 8'(x.C);
        endcase
    endfunction
    // raw stamps (the latency is added / subtracted at use)
    wire [15:0] rw_e  = lst(e.rdk),  rw_e2 = lst(e2.rdk);
    wire [15:0] ra_a  = lst(a.rak),  ra_a2 = lst(a2.rak);
    wire        rok_a   = !a.rav  || (!go && lsv(a.rak)  && le_n(ra_a,  6'(a.ral)));
    wire        rok_a2  = !a2.rav || (!go && lsv(a2.rak) && le_n(ra_a2, 6'(a2.ral)));
    wire        rokO_a  = !a.rav  || (!go && lsv(a.rak)  && le_n(ra_a,  6'(a.ral) + 6'(OVH)));
    wire        rokO_a2 = !a2.rav || (!go && lsv(a2.rak) && le_n(ra_a2, 6'(a2.ral) + 6'(OVH)));
    wire [17:0] nc_a  = 18'(nowp) + 18'(cnof(a)),  nc_a2 = 18'(nowp) + 18'(cnof(a2));
    always_ff @(posedge clk) begin
        rwH <= e_pop ? rw_e2 : rw_e;
        raH <= s_fire ? ra_a2 : ra_a;
`ifdef QBT_MUT_RTB
        rok  <= 1'b1;                                                    // mutant: token RAW readiness dropped
        rokO <= 1'b1;
`else
        rok  <= s_fire ? rok_a2 : rok_a;
        rokO <= s_fire ? rokO_a2 : rokO_a;
`endif
        NC   <= s_fire ? nc_a2 : nc_a;
        NC4  <= (s_fire ? nc_a2 : nc_a) - 18'd4;
        NC32 <= (s_fire ? nc_a2 : nc_a) - 18'd32;
        pc_hq <= 8'($countones(fs_hq)); pc_hqd <= 8'($countones(fs_hqd)); pc_z <= 8'($countones(fs_z));
    end

    // ---------------------------------------------------------------- end phase (comb, registered e)
    logic        ce_ev;
    logic [15:0] ce, rw, cap, ds, de, lane_u, ln;
`ifdef QBT_MUT_RTW
    wire  [15:0] rwb = rwH;                                              // mutant: drain-read RAW bypass dropped
`else
    wire  [15:0] rwb = (cm_v && e.rdk == cm_k) ? cm_de : rwH;            // stamp[rdk] incl. this cycle's commit
`endif
    logic [15:0] t_arr_n, t_sh_n, lane_f_n, lane_w_n;
    logic        last_v_n, lbc2_n;
    logic [4:0]  last_pi_n;
    logic        e_err;
    assign ce_ev = d_vld && d_eot;
    logic kelt;                                                          // ke < nt (registered)
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) kelt <= 1'b0;
        else kelt <= (go ? 10'd0 : e_pop ? ke + 10'd1 : ke) < nt;
    // max of 4 by parallel pairwise compares (one select level after the comparators)
    function automatic logic [1:0] amax4(input logic [15:0] x0, x1, x2, x3);
        logic g01, g02, g03, g12, g13, g23;
        g01 = x0 >= x1; g02 = x0 >= x2; g03 = x0 >= x3; g12 = x1 >= x2; g13 = x1 >= x3; g23 = x2 >= x3;
        if (g01 && g02 && g03) return 2'd0;
        if (!g01 && g12 && g13) return 2'd1;
        if (!g02 && !g12 && g23) return 2'd2;
        return 2'd3;
    endfunction
    always_comb begin
        p_arr = run && kelt && e.arr && (ce_p || ce_ev);
        p_ppu = run && kelt && !e.arr;
        ce = ce_p ? ce_q : now;
        rw = !e.rdv ? 16'd0 : rwb + 16'(e.rdl);
        lane_u = e.u == 2'd2 ? lane_w : lane_f;
        ln = lane_u + 16'(lbc2 && e.hm && e.u == 2'd1);
        cap = '0; ds = '0; de = '0;
        t_arr_n = t_arr; t_sh_n = t_sh; lane_f_n = lane_f; lane_w_n = lane_w; last_v_n = last_v; last_pi_n = last_pi;
        lbc2_n = lbc2;
        e_err = e_pop && e.rdv && !lsv(e.rdk);
        if (p_arr) begin
            if (e.u == 2'd0) begin cap = ce; ds = ce; de = ce; end
            else begin
                logic [1:0] im;  logic [15:0] dr;
                dr  = e.u == 2'd2 ? 16'd32 : 16'd4;
                cap = mx(ce, t_sh);
                im  = amax4(ce, t_sh, lane_u, rw);
                ds  = im == 2'd0 ? ce : im == 2'd1 ? t_sh : im == 2'd2 ? lane_u : rw;
                de  = im == 2'd0 ? ce + dr : im == 2'd1 ? t_sh + dr : im == 2'd2 ? lane_u + dr : rw + dr;
                t_sh_n = de;
                if (e.u == 2'd2) lane_w_n = de; else begin lane_f_n = de; lbc2_n = e.bc2; end
            end
            t_arr_n = cap; last_v_n = 1'b1; last_pi_n = e.pi;
            if (cap < now || ds < now) e_err = 1'b1;
        end else if (p_ppu) begin
            ds = mx(ln, rw) + ((e.first && rw > ln) ? 16'(OVH) : 16'd0);
            de = ds + (e.u == 2'd2 ? 16'd32 : 16'd4);
            if (e.u == 2'd2) lane_w_n = de; else begin lane_f_n = de; lbc2_n = 1'b0; end
            if (ds < now) e_err = 1'b1;
        end
    end

    // ---------------------------------------------------------------- start phase: token of ks (parallel compares)
    // S0: no array commit in this cycle (registered state only); S1: the head of the end FIFO commits now (its cap / de
    // enter as parallel compares); s_fire = p_arr ? S1 : S0 (p_arr = a few gates after the act supply's d_eot register)
    logic S0, S1;
    always_comb begin
        logic [17:0] ncd;
        logic sh0, sh1, ra0, ra1;
        ncd = e.u == 2'd2 ? NC32 : NC4;
        sh0 = a.u == 2'd0 || 18'(t_sh) <= NC;
        sh1 = a.u == 2'd0 || (e.u == 2'd0 ? 18'(t_sh) <= NC :
              ($signed({2'b0, ce}) <= $signed(ncd) && $signed({2'b0, t_sh}) <= $signed(ncd) &&
               $signed({2'b0, lane_u}) <= $signed(ncd) &&
               (e.rdv ? $signed({2'b0, rwb}) <= $signed(ncd) - $signed({13'd0, e.rdl}) : $signed(18'd0) <= $signed(ncd))));
        // ra > x  <=>  rav && raw stamp > x - ral
        ra0 = rok && (!((!last_v || last_pi != a.pi) && a.rav && $signed({2'b0, raH}) > $signed({2'b0, t_arr}) - $signed({13'd0, a.ral})) || rokO);
        ra1 = rok && (!(e.pi != a.pi && a.rav && $signed({2'b0, raH}) > $signed({2'b0, ce}) - $signed({13'd0, a.ral}) &&
                        (e.u == 2'd0 || $signed({2'b0, raH}) > $signed({2'b0, t_sh}) - $signed({13'd0, a.ral}))) || rokO);
        S0  = (!kpv || ke > kprev) && t_arr <= now && ra0 && sh0;
        S1  = (!kpv || ke >= kprev) && (e.u == 2'd0 || t_sh <= now) && ra1 && sh1;
        s_fire = run && ksv && (p_arr ? S1 : S0);
        tgo = s_fire ? (a.ctx ? 2'b10 : 2'b01) : 2'b00;
    end

    // ---------------------------------------------------------------- capture event / PPU job queues (as R3b)
    always_comb begin
        c_fire = 1'b0; c_cmp = 1'b0; c_pi = '0; c_tp = '0; c_ct = '0;
        if (cp_v && cp_t == now) begin c_fire = 1'b1; c_cmp = cp_cmp; c_pi = cp_pi; c_tp = cp_tp; c_ct = cp_ct; end
        else if (p_arr && cap == now) begin c_fire = 1'b1; c_cmp = e.u == 2'd0; c_pi = e.pi; c_tp = e.tp; c_ct = e.ct; end
    end
    wire        j_push = (p_arr && e.u != 2'd0) || p_ppu;
    wire        j_wide = e.u == 2'd2;
    wire [15:0] j_job = {e.ct, e.tp, e.pi};
    wire        fq_e = fq_w == fq_r, wq_e = wq_w == wq_r;
    wire [31:0] fh = fq[fq_r[4:0]], whd = wq[wq_r[2:0]];
    wire        f_head = !fq_e && fh[31:16] == now, w_head = !wq_e && whd[31:16] == now;
    wire        f_byp = j_push && !j_wide && fq_e && ds == now, w_byp = j_push && j_wide && wq_e && ds == now;
    assign f_fire = f_head || f_byp;
    assign f_job  = f_head ? fh[15:0] : j_job;
    assign w_fire = w_head || w_byp;
    assign w_job  = w_head ? whd[15:0] : j_job;

    // ---------------------------------------------------------------- pass starts (as R3b)
    logic [5:0] pp [2];
    logic [1:0] done_q;
    for (genvar c = 0; c < 2; c++) begin : g_ps
        // registered pass start (R3b: run && pp < n_pq && (pp == 0 ? now == 0 : done_q), from the previous cycle's
        // go / done / pp: now == 0 with run <=> go in the previous cycle)
        logic pf_r;
        wire [5:0] ppn = go ? 6'd0 : p_fire[c] ? pp[c] + 6'd1 : pp[c];
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) pf_r <= 1'b0;
            else pf_r <= (go || run) && ppn < n_pq[c] && (ppn == '0 ? go : done[c]);
        assign p_fire[c] = pf_r;
`ifndef SYNTHESIS
        always @(posedge clk) if (rst_n && pf_r != (run && pp[c] < n_pq[c] && (pp[c] == '0 ? now == 16'd0 : done_q[c])))
            $error("qb_seq_rt: registered pass start differs on context %0d (now %0d)", c, now);
`endif
        assign p_pi[c] = pq[c][pp[c][4:0]];
    end

    // ---------------------------------------------------------------- load permissions (window + prefetch)
    logic [10:0] pnw_hq, pnw_hqd, pnw_z;                                 // executed S words per channel tile (registered)
    always_ff @(posedge clk) begin
        logic [31:0] zq;
        for (int i = 0; i < 32; i++) zq[i] = |fs_z[4 * i +: 4];
        pnw_hq <= 11'($countones(fs_hq)); pnw_hqd <= 11'(2 * $countones(fs_hqd)); pnw_z <= 11'($countones(zq));
    end
    function automatic logic [10:0] nwof(input logic [3:0] cf);
        return cf == 4'd8 ? pnw_hq : cf == 4'd9 ? pnw_hqd : pnw_z;
    endfunction
    // readiness of entry w in the next cycle (commits up to this cycle - 1; see header)
    function automatic logic rdn(input logic [LTW-1:0] w);
        return !w[10] || (!go && lsv(w[20:11]) && le_n(lst(w[20:11]), 6'(w[25:21])));
    endfunction
    logic [15:0] lseq [2];
    logic [1:0]  cval, pf_ok;  logic [4:0] cpi [2];
    for (genvar c = 0; c < 2; c++) begin : g_lp
        logic [9:0]     lptr, lend, kA, lp3;                             // lp3 = lptr + 3
        logic [LTW-1:0] wA, wB, wC;
        logic           RdA, RdB, AinL, BinL, CinL, i8r;
        logic [3:0]     cfr;
        logic [11:0]    EA, EB;
        // next-pass prefetch: pass index -> pass table fields -> first 3 entries (one lt read per cycle)
        logic [4:0]     nx_pi;  logic [9:0] nx_lb, nx_lc;  logic nx_i8;  logic [3:0] nx_cf;
        logic [LTW-1:0] nx_w [3];
        logic [1:0]     pf_i;  logic [2:0] pf_age;  logic [4:0] ppn_q;
        wire  [4:0]     ppn = pp[c] < n_pq[c] ? pp[c][4:0] : 5'd0;
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) begin pf_i <= '0; pf_age <= '0; ppn_q <= '0; end
            else begin
                logic [95:0] q;
                q = pt[nx_pi];
                nx_pi <= pq[c][ppn];
                nx_lb <= q[78:69]; nx_lc <= q[88:79]; nx_i8 <= q[20]; nx_cf <= q[3:0];
                nx_w[pf_i] <= lt[nx_lb + 10'(pf_i)];
                pf_i <= pf_i == 2'd2 ? 2'd0 : pf_i + 2'd1;
                ppn_q <= ppn;
                pf_age <= (ppn != ppn_q || wpg || (h_we && h_sel == 4'd3)) ? 3'd0 : (pf_age == 3'd7 ? 3'd7 : pf_age + 3'd1);
            end
        assign pf_ok[c] = pf_age >= 3'd6;
        wire [9:0]  pos = c ? l_pos1 : l_pos0;
        wire        adv = AinL && EA <= {2'b0, pos} && (!i8r || RdA);
        wire [1:0]  qs_ = cfr == 4'd8 ? 2'd0 : cfr == 4'd9 ? 2'd1 : 2'd2;
        assign l_ok[c] = cval[c] && !p_fire[c] && (adv ? (BinL && EB > {2'b0, pos} && RdB) : (AinL && EA > {2'b0, pos} && RdA)) &&
                         (!i8r || fl_quiet[qs_]);
        assign lseq[c] = 16'(adv ? wB[LTW-1:26] : wA[LTW-1:26]);
        // lookups for the next cycle (address muxed to the prefetched entries at a pass start)
        wire        r0 = rdn(p_fire[c] ? nx_w[0] : wA), r1 = rdn(p_fire[c] ? nx_w[1] : wB), r2 = rdn(wC);
        wire [10:0] nw = nwof(cfr), nwn = nwof(nx_cf);
        wire [11:0] P0 = 12'(kA * nw), P1 = P0 + 12'(nw), P2 = P1 + 12'(nw);
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) begin
                cval[c] <= 1'b0; cpi[c] <= '0; lptr <= '0; lend <= '0; kA <= 10'd1; lp3 <= 10'd3; AinL <= 1'b0; BinL <= 1'b0; CinL <= 1'b0;
                i8r <= 1'b0; cfr <= '0;
            end else if (go) cval[c] <= 1'b0;
            else if (p_fire[c]) begin
                cval[c] <= 1'b1; cpi[c] <= p_pi[c];
                lptr <= nx_lb; lend <= nx_lb + nx_lc; kA <= 10'd1; lp3 <= nx_lb + 10'd3;
                AinL <= nx_lc > 10'd0; BinL <= nx_lc > 10'd1; CinL <= nx_lc > 10'd2;
                wA <= nx_w[0]; wB <= nx_w[1]; wC <= nx_w[2];
                RdA <= r0; RdB <= r1;
                i8r <= nx_i8; cfr <= nx_cf;
                EA <= nx_i8 ? 12'(nwn) : 12'(nx_w[0][9:0]);
                EB <= nx_i8 ? 12'(2 * nwn) : 12'(nx_w[1][9:0]);
            end else if (adv) begin
                lptr <= lptr + 10'd1; kA <= kA + 10'd1; lp3 <= lp3 + 10'd1;
                AinL <= BinL; BinL <= CinL; CinL <= lp3 < lend;
`ifdef QBT_MUT_RTL
                wA <= wB; wB <= wC; wC <= lt[lp3 - 10'd1];              // mutant: window refill one entry short
`else
                wA <= wB; wB <= wC; wC <= lt[lp3];
`endif
                RdA <= r1; RdB <= r2;
                EA <= i8r ? P1 : 12'(wB[9:0]);
                EB <= i8r ? P2 : 12'(wC[9:0]);
            end else begin
                RdA <= r0; RdB <= r1;
                EA <= i8r ? P0 : 12'(wA[9:0]);
                EB <= i8r ? P1 : 12'(wB[9:0]);
            end
`ifndef SYNTHESIS
        always @(posedge clk) if (rst_n && p_fire[c] && pf_age < 3'd6)
            $error("qb_seq_rt: pass start on context %0d before the next-pass prefetch settled (now %0d)", c, now);
`endif
    end
    assign l_seq0 = lseq[0];
    assign l_seq1 = lseq[1];

    // ---------------------------------------------------------------- state update
    wire pf_err = |(p_fire & ~pf_ok);
    always_ff @(posedge clk) if (cm_v) stb[cm_k] <= cm_de;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            ke <= '0; ks <= '0; kprev <= '0; ksv <= 1'b0; kpv <= 1'b0; ce_p <= 1'b0; ce_q <= '0; last_v <= 1'b0;
            last_pi <= '0; lbc2 <= 1'b0; t_arr <= '0; t_sh <= '0; lane_f <= '0; lane_w <= '0; svb <= '0; cp_v <= 1'b0;
            fq_w <= '0; fq_r <= '0; wq_w <= '0; wq_r <= '0; pp[0] <= '0; pp[1] <= '0; done_q <= '0; err <= 1'b0;
            cm_v <= 1'b0;
        end else if (go) begin
            ke <= '0; ks <= ks0; kprev <= '0; ksv <= 1'b1; kpv <= 1'b0; ce_p <= 1'b0; last_v <= 1'b0; lbc2 <= 1'b0;
            t_arr <= '0; t_sh <= '0; lane_f <= '0; lane_w <= '0; svb <= '0; cp_v <= 1'b0;
            fq_w <= '0; fq_r <= '0; wq_w <= '0; wq_r <= '0; pp[0] <= '0; pp[1] <= '0; done_q <= '0; err <= 1'b0;
            cm_v <= 1'b0;
        end else begin
            done_q <= done;
            for (int c = 0; c < 2; c++) if (p_fire[c]) pp[c] <= pp[c] + 6'd1;
            t_arr <= t_arr_n; t_sh <= t_sh_n; lane_f <= lane_f_n; lane_w <= lane_w_n; last_v <= last_v_n;
            last_pi <= last_pi_n; lbc2 <= lbc2_n;
            if (cm_v) svb[cm_k] <= 1'b1;
            cm_v <= e_pop;
            if (e_pop) begin ke <= ke + 10'd1; cm_k <= ke; cm_de <= de; end
            if (p_arr) ce_p <= 1'b0;
            if (ce_ev && !(p_arr && !ce_p)) begin
                if (ce_p) err <= 1'b1;
                ce_p <= 1'b1; ce_q <= now;
            end
            if (cp_v && cp_t == now) cp_v <= 1'b0;
            if (p_arr && cap != now) begin
                if (cp_v && cp_t != now) err <= 1'b1;
                cp_v <= 1'b1; cp_t <= cap; cp_cmp <= e.u == 2'd0; cp_pi <= e.pi; cp_tp <= e.tp; cp_ct <= e.ct;
            end
            if (cp_v && cp_t < now) err <= 1'b1;
            if (f_head) fq_r <= fq_r + 6'd1;
            if (w_head) wq_r <= wq_r + 4'd1;
            if (j_push && !j_wide && !f_byp) begin fq[fq_w[4:0]] <= {ds, j_job}; fq_w <= fq_w + 6'd1; end
            if (j_push && j_wide && !w_byp) begin wq[wq_w[2:0]] <= {ds, j_job}; wq_w <= wq_w + 4'd1; end
            if ((f_head && f_byp) || (w_head && w_byp) || (!fq_e && fh[31:16] < now) || (!wq_e && whd[31:16] < now) ||
                fq_w - fq_r > 6'(FD - 1) || wq_w - wq_r > 4'(WD - 1)) err <= 1'b1;
            if (e_err) err <= 1'b1;
            // prefetch FIFOs must hold the 2nd entry when popping (lookups one cycle ahead), next-pass prefetch settled
            if ((e_pop && ec < 3'd2) || (s_fire && fc < 3'd2) || pf_err) err <= 1'b1;
            if (s_fire) begin ks <= a.nxa; ksv <= a.nxv; kprev <= ks; kpv <= 1'b1; end
        end
`ifndef SYNTHESIS
    // exactness argument of the registered token / load-permission readiness: a pecmp commit is never >= 9 cycles
    // behind its ce (RAW latencies of the program are >= 11)
    always @(posedge clk) if (rst_n && !go && p_arr && e.u == 2'd0 && now - ce >= 16'd9)
        $error("qb_seq_rt: pecmp commit %0d cycles after its ce (now %0d ke %0d)", now - ce, now, ke);
    always @(posedge clk) if (rst_n && !go && ((e_pop && ec < 3'd2) || (s_fire && fc < 3'd2)))
        $error("qb_seq_rt: prefetch FIFO below 2 entries at a pop (now %0d ke %0d ec %0d fc %0d)", now, ke, ec, fc);
`endif
endmodule
