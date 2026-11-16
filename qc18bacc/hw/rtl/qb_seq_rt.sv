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
// R8a timing defines (default off = R4b code; same cycles, checked against the R4b lookups in simulation unless
// QBS_NOCHK):
//   QB_SEQ_LPS: load permissions: per window slot (A, B, C, next-pass 0..2) a stamp register {svb, stb}[key] kept by
//     commit snooping (pass start pf_r -> address mux -> stamp table read -> compare -> RdA cut to register -> compare);
//     table reads only at register addresses: wD = lt[lp3] (prefetched, lt writes bypassed) entering C, and the
//     nx_w entry written in the previous cycle (next-pass prefetch period 4, nx_w[3] -> wD at a pass start);
//   QB_SEQ_CMH: commit bypass hit (cm_v && e.rdk == cm_k) registered; rw candidates compared in parallel; the
//     end-phase late check uses cap < now (ds >= cap);
//   QB_SEQ_TKS: token RAW readiness from per-entry stamp registers of a 5-deep start FIFO (entries land at index >= 2,
//     looked up in the next cycle at a registered key; landing at 0 / 1 under run = err).
//   QB_SEQ_DSP (round 2, with CMH): end-phase compares as carry-save signs (no stamp + rdl adder in front), ds / de
//     values as register sums beside them, ds == now per candidate (f_fire / w_fire);
//   QB_SEQ_TGO (round 2, with CMH): token sh1 compared for both drain lengths in parallel (e.u selects after), RAW
//     compares as carry-save signs.
// R8d timing define (default off; needs QB_SEQ_DSP):
//   QB_SEQ_DEP: end-phase de / ds candidates as separate sums of registers (ce + dr, t_sh + dr, lane + dr, stamp + rdl
//     (+ OVH) + dr) selected after the compares (DC had shared one adder behind the compare-driven select), and the
//     PPU-tile compare rw > ln as one carry-save sign per lane (lane_f + bc2 inc / lane_w; e.u selects after); the
//     token-start compares on ce (= ce_p ? ce_q : now -> tgo) done for ce_q and now in parallel, ce_p selects after.
//     Mutants QBS_MUT_DEP = 1..4 (see k_lwd).
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
`ifdef QB_SEQ_TKS
    localparam int SQD = 5;                                              // R8a: 5 deep (entries land at index >= 2)
`else
    localparam int SQD = FQD;
`endif
    logic [79:0] sqf [SQD];  logic [79:0] qs;                            // shift FIFO: sqf[0] = head
    logic [2:0]  fc;  logic inf, pv;  logic [9:0] fa;
    wire  [9:0]  na = inf ? (qs[73] ? qs[72:63] : ks0) : fa;
    wire         issue = pv && !wh && !wk0 && (32'(fc) + 32'(inf) < SQD);
    qbt_rfsp #(80, NDM) u_ds (.clk, .ren(issue), .we(wh), .a(wh ? DAW'(h_addr) : DAW'(na)), .wd(h_d[79:0]), .q(qs));
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin fc <= '0; inf <= 1'b0; pv <= 1'b0; fa <= '0; end
        else if (wh || wk0) begin
            fc <= '0; inf <= 1'b0; pv <= 1'b1; fa <= wk0 ? h_d[9:0] : ks0;
        end else begin
            inf <= issue;
            for (int i = 0; i < SQD; i++)
                if (inf && i == int'(fc) - int'(s_fire)) sqf[i] <= qs;
                else if (s_fire && i + 1 < SQD) sqf[i] <= sqf[(i + 1) % SQD];
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
`ifdef QB_SEQ_RAL
    logic [16:0] raL;                                                    // R8a round 3: raH + ral (registered)
`endif
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
`ifdef QB_SEQ_TKS
    // R8a: stamp registers SQ[i] = {svb, stb}[rak of sqf[i]] of the table in this cycle (pending write cm bypassed at
    // use), kept by snooping the commits and shifting with the FIFO; an entry landing in the FIFO is looked up in the
    // next cycle at a registered key (kq), so it must land at index >= 2 (5-deep FIFO: steady back-to-back tokens
    // keep 3 entries; err otherwise, as the fc < 2 rule).  Readiness = compare after registers.
    logic [16:0] SQ [SQD];  logic [9:0] kq;  logic lv;  logic [2:0] lidx;
    dsc_t qsd, sqd [SQD];                                                // decoded FIFO words (DC: no select on a call)
    assign qsd = dget(qs);
    for (genvar i = 0; i < SQD; i++) begin : g_sqd
        assign sqd[i] = dget(sqf[i]);
    end
    wire  [16:0] tq = {svb[kq], stb[kq]};                                // the one table read (register address)
    function automatic logic [16:0] snq(input logic [9:0] k, input logic [16:0] x);
`ifdef QBS_MUT_TKS
        return x;                                                        // mutant: commits not snooped
`else
        return (cm_v && cm_k == k) ? {1'b1, cm_de} : x;
`endif
    endfunction
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin lv <= 1'b0; lidx <= '0; kq <= '0; for (int i = 0; i < SQD; i++) SQ[i] <= '0; end
        else begin
            lv <= !(wh || wk0) && inf;
            lidx <= fc - 3'(s_fire);
            kq <= qsd.rak;
            for (int i = 0; i < SQD; i++) begin
                logic [16:0] n;  int j;
                j = (!(wh || wk0) && s_fire) ? i + 1 : i;
                if (j >= SQD) n = SQ[i];
                else if (lv && 3'(j) == lidx) n = snq(kq, tq);
                else n = snq(sqd[j].rak, SQ[j]);
                SQ[i] <= {n[16] && !go, n[15:0]};
            end
        end
    wire        hq0 = cm_v && a.rak == cm_k,  hq1 = cm_v && a2.rak == cm_k;
    wire [15:0] ra_a  = hq0 ? cm_de : SQ[0][15:0],  ra_a2 = hq1 ? cm_de : SQ[1][15:0];
    wire        sv0 = SQ[0][16] || hq0,  sv1 = SQ[1][16] || hq1;
    wire        rok_a   = !a.rav  || (!go && sv0 && le_n(ra_a,  6'(a.ral)));
    wire        rok_a2  = !a2.rav || (!go && sv1 && le_n(ra_a2, 6'(a2.ral)));
    wire        rokO_a  = !a.rav  || (!go && sv0 && le_n(ra_a,  6'(a.ral) + 6'(OVH)));
    wire        rokO_a2 = !a2.rav || (!go && sv1 && le_n(ra_a2, 6'(a2.ral) + 6'(OVH)));
    wire        tk_err = inf && fc - 3'(s_fire) < 3'd2;                  // landing at index 0 / 1 (checked under run)
`ifndef SYNTHESIS
`ifndef QBS_NOCHK
    wire [15:0] o_ra_a = lst(a.rak), o_ra_a2 = lst(a2.rak);
    wire        o_rok_a  = !a.rav  || (!go && lsv(a.rak)  && le_n(o_ra_a,  6'(a.ral)));
    wire        o_rok_a2 = !a2.rav || (!go && lsv(a2.rak) && le_n(o_ra_a2, 6'(a2.ral)));
    wire        o_rokO_a  = !a.rav  || (!go && lsv(a.rak)  && le_n(o_ra_a,  6'(a.ral) + 6'(OVH)));
    wire        o_rokO_a2 = !a2.rav || (!go && lsv(a2.rak) && le_n(o_ra_a2, 6'(a2.ral) + 6'(OVH)));
    always @(posedge clk) if (rst_n && run && ksv && (s_fire ? {rok_a2, rokO_a2, ra_a2} != {o_rok_a2, o_rokO_a2, o_ra_a2} :
                                                               {rok_a, rokO_a, ra_a} != {o_rok_a, o_rokO_a, o_ra_a}))
        $error("qb_seq_rt: registered token stamps differ (now %0d ks %0d fc %0d)", now, ks, fc);
`endif
`endif
`else
    wire [15:0] ra_a  = lst(a.rak),  ra_a2 = lst(a2.rak);
    wire        rok_a   = !a.rav  || (!go && lsv(a.rak)  && le_n(ra_a,  6'(a.ral)));
    wire        rok_a2  = !a2.rav || (!go && lsv(a2.rak) && le_n(ra_a2, 6'(a2.ral)));
    wire        rokO_a  = !a.rav  || (!go && lsv(a.rak)  && le_n(ra_a,  6'(a.ral) + 6'(OVH)));
    wire        rokO_a2 = !a2.rav || (!go && lsv(a2.rak) && le_n(ra_a2, 6'(a2.ral) + 6'(OVH)));
`endif
    wire [17:0] nc_a  = 18'(nowp) + 18'(cnof(a)),  nc_a2 = 18'(nowp) + 18'(cnof(a2));
    always_ff @(posedge clk) begin
        rwH <= e_pop ? rw_e2 : rw_e;
        raH <= s_fire ? ra_a2 : ra_a;
`ifdef QB_SEQ_RAL
`ifdef QBS_MUT_RAL
        raL <= s_fire ? 17'(ra_a2) : 17'(ra_a);                         // mutant: latency not added
`else
        raL <= s_fire ? 17'(ra_a2) + 17'(a2.ral) : 17'(ra_a) + 17'(a.ral);   // stamp + ral of the next head
`endif
`endif
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
`ifdef QB_SEQ_CMH
    // R8a: the bypass hit (cm_v && e.rdk == cm_k) is a register: next cm_v / cm_k = this cycle's commit (ke), next
    // e.rdk = the 2nd end FIFO entry at a pop (landing at the head only with ec = 1 = err, still covered)
    logic        hitR;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) hitR <= 1'b0;
        else begin
            dsc_t eq_;
            eq_ = dget(qe);
            hitR <= !go && e_pop && ((wh || wnt) ? e.rdk == ke : (einf && ec == 3'd1) ? eq_.rdk == ke : e2.rdk == ke);
        end
`ifndef SYNTHESIS
`ifndef QBS_NOCHK
    always @(posedge clk) if (rst_n && hitR != (cm_v && e.rdk == cm_k))
        $error("qb_seq_rt: registered commit-bypass hit differs (now %0d ke %0d)", now, ke);
`endif
`endif
`ifdef QBT_MUT_RTW
    wire  [15:0] rwb = rwH;                                              // mutant: drain-read RAW bypass dropped
`else
    wire  [15:0] rwb = hitR ? cm_de : rwH;                               // stamp[rdk] incl. this cycle's commit
`endif
`elsif QBT_MUT_RTW
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
`ifdef QB_SEQ_DEP
`ifndef QBS_MUT_DEP
`define QBS_MUT_DEP 0
`endif
    // R8d: candidate sums (registers only) beside the compares
    wire        k_inc = lbc2 && e.hm && e.u == 2'd1;
    wire [15:0] k_ce  = ce_p ? ce_q : now;
    wire [15:0] k_dr  = e.u == 2'd2 ? 16'd32 : 16'd4;
    wire [15:0] k_rs  = hitR ? cm_de : rwH;
    wire [15:0] k_ov  = e.first ? 16'(OVH) : 16'd0;
    // each candidate sum in its own instance (qbs_add3; the flow keeps hierarchy): DC cannot share one adder behind the
    // compare-driven select
    wire [15:0] k_ovdr = k_ov + k_dr;
    wire [15:0] k_ced, k_tsd, k_lfd, k_lfa, k_lwd, k_rs3, k_rso;
    // mutants QBS_MUT_DEP = 1: wide lane with the fused drain, 2: PPU RAW candidate without OVH, 3: ce candidate with
    // the fused drain, 4: RAW candidate (array tile) without rdl
    qbs_add3 u_ced (.a(k_ce),   .b(`QBS_MUT_DEP == 3 ? 16'd4 : k_dr), .c(16'd0), .s(k_ced));
    qbs_add3 u_tsd (.a(t_sh),   .b(k_dr),  .c(16'd0),           .s(k_tsd));
    qbs_add3 u_lfd (.a(lane_f), .b(16'd4), .c(16'(k_inc)),      .s(k_lfd));   // ln + dr, e.u != 2 (PPU tile)
    qbs_add3 u_lfa (.a(lane_f), .b(16'd4), .c(16'd0),           .s(k_lfa));   // lane_u + dr, e.u != 2 (array tile)
    qbs_add3 u_lwd (.a(lane_w), .b(`QBS_MUT_DEP == 1 ? 16'd4 : 16'd32), .c(16'd0), .s(k_lwd));
    qbs_add3 u_rs3 (.a(k_rs),   .b(`QBS_MUT_DEP == 4 ? 16'd0 : 16'(e.rdl)), .c(k_dr), .s(k_rs3));
    qbs_add3 u_rso (.a(k_rs),   .b(16'(e.rdl)), .c(`QBS_MUT_DEP == 2 ? k_dr : k_ovdr), .s(k_rso));
    wire [15:0] k_rwd  = !e.rdv ? k_dr : k_rs3;
    wire [15:0] k_rwod = !e.rdv ? k_ovdr : k_rso;
    // rw <= ln (x - stamp - rdl >= 0 with x = lane_f + inc / lane_w), both stamps, both lanes
    wire        k_gfc = $signed({3'b0, lane_f}) + $signed({18'b0, k_inc}) - $signed({3'b0, cm_de}) - $signed({14'b0, e.rdl}) >= 19'sd0;
    wire        k_gfh = $signed({3'b0, lane_f}) + $signed({18'b0, k_inc}) - $signed({3'b0, rwH}) - $signed({14'b0, e.rdl}) >= 19'sd0;
    wire        k_gwc = $signed({3'b0, lane_w}) - $signed({3'b0, cm_de}) - $signed({14'b0, e.rdl}) >= 19'sd0;
    wire        k_gwh = $signed({3'b0, lane_w}) - $signed({3'b0, rwH}) - $signed({14'b0, e.rdl}) >= 19'sd0;
    wire        k_gln = !e.rdv || (e.u == 2'd2 ? (hitR ? k_gwc : k_gwh) : (hitR ? k_gfc : k_gfh));
    // token start: the ce terms (ce = ce_p ? ce_q : now) compared for both sources, ce_p selects after
    wire        k_ce4q  = $signed({2'b0, ce_q}) <= $signed(NC4),   k_ce4n  = $signed({2'b0, now}) <= $signed(NC4);
    wire        k_ce32q = $signed({2'b0, ce_q}) <= $signed(NC32),  k_ce32n = $signed({2'b0, now}) <= $signed(NC32);
    wire        k_ce4 = ce_p ? k_ce4q : k_ce4n,  k_ce32 = ce_p ? k_ce32q : k_ce32n;
`ifdef QB_SEQ_RAL
    wire        k_rceq  = raL > 17'(ce_q),  k_rcen = raL > 17'(now);
    wire        k_rce = ce_p ? k_rceq : k_rcen;
`endif
`endif
`ifdef QB_SEQ_DSP
    // R8a round 2 (needs QB_SEQ_CMH): no adder in front of the end-phase compares: x >= rw (rw = rdv ? stamp + rdl :
    // 0) is the sign of x - stamp - rdl (one carry-save level + compare, both stamp candidates, hitR selects); the
    // values (ds, de) are sums of registers beside the compares; ds == now is compared per candidate (f_fire / w_fire).
    // Exact while stamp + rdl < 2^16 (checked in simulation; times are < 2^16 - 64 per image).
    logic dsnow;
    function automatic logic gerw(input logic [15:0] x);                 // x >= rw
        logic gc, gh;
        gc = $signed({3'b0, x}) - $signed({3'b0, cm_de}) - $signed({14'b0, e.rdl}) >= 19'sd0;
        gh = $signed({3'b0, x}) - $signed({3'b0, rwH}) - $signed({14'b0, e.rdl}) >= 19'sd0;
        return !e.rdv || (hitR ? gc : gh);
    endfunction
    function automatic logic [1:0] amax4g(input logic g01, g02, g03, g12, g13, g23);
        if (g01 && g02 && g03) return 2'd0;
        if (!g01 && g12 && g13) return 2'd1;
        if (!g02 && !g12 && g23) return 2'd2;
        return 2'd3;
    endfunction
`endif
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
`ifdef QB_SEQ_CMH
        e_err = e_pop && e.rdv && !(svb[e.rdk] || hitR);
`else
        e_err = e_pop && e.rdv && !lsv(e.rdk);
`endif
`ifdef QB_SEQ_DSP
        dsnow = now == 16'd0;
        if (p_arr) begin
            if (e.u == 2'd0) begin cap = ce; ds = ce; de = ce; dsnow = ce == now; end
            else begin
                logic [1:0] im;  logic [15:0] dr, rs, rw0, rwd;  logic g03, g13, g23;
                dr  = e.u == 2'd2 ? 16'd32 : 16'd4;
                rs  = hitR ? cm_de : rwH;
                rw0 = !e.rdv ? 16'd0 : rs + 16'(e.rdl);
`ifdef QBS_MUT_DSP
                rwd = !e.rdv ? dr : rs + dr;                             // mutant: drain end of the RAW candidate without rdl
`else
                rwd = !e.rdv ? dr : rs + 16'(e.rdl) + dr;
`endif
                cap = mx(ce, t_sh);
                g03 = gerw(ce);  g13 = gerw(t_sh);
                g23 = gerw(lane_u);
                im  = amax4g(ce >= t_sh, ce >= lane_u, g03, t_sh >= lane_u, g13, g23);
                ds  = im == 2'd0 ? ce : im == 2'd1 ? t_sh : im == 2'd2 ? lane_u : rw0;
`ifdef QB_SEQ_DEP
                de  = im == 2'd0 ? k_ced : im == 2'd1 ? k_tsd : im == 2'd2 ? (e.u == 2'd2 ? k_lwd : k_lfa) : k_rwd;
`else
                de  = im == 2'd0 ? ce + dr : im == 2'd1 ? t_sh + dr : im == 2'd2 ? lane_u + dr : rwd;
`endif
                dsnow = im == 2'd0 ? ce == now : im == 2'd1 ? t_sh == now : im == 2'd2 ? lane_u == now :
                        (!e.rdv ? now == 16'd0 : rs == now - 16'(e.rdl));
                t_sh_n = de;
                if (e.u == 2'd2) lane_w_n = de; else begin lane_f_n = de; lbc2_n = e.bc2; end
            end
            t_arr_n = cap; last_v_n = 1'b1; last_pi_n = e.pi;
            if (ce < now && (e.u == 2'd0 || t_sh < now)) e_err = 1'b1;
        end else if (p_ppu) begin
            logic c;  logic [15:0] dr, ov, rs, rwo, rwod;
            dr   = e.u == 2'd2 ? 16'd32 : 16'd4;
            ov   = e.first ? 16'(OVH) : 16'd0;
            rs   = hitR ? cm_de : rwH;
            rwo  = !e.rdv ? ov : rs + 16'(e.rdl) + ov;                   // rw + OVH (first tile)
            rwod = !e.rdv ? ov + dr : rs + 16'(e.rdl) + ov + dr;
`ifdef QB_SEQ_DEP
            c    = !k_gln;                                               // rw > ln
            ds   = c ? rwo : ln;
            de   = c ? k_rwod : (e.u == 2'd2 ? k_lwd : k_lfd);
`else
            c    = !gerw(ln);                                            // rw > ln
            ds   = c ? rwo : ln;
            de   = c ? rwod : ln + dr;
`endif
            dsnow = c ? (!e.rdv ? ov == now : rs == now - 16'(e.rdl) - ov) : ln == now;
            if (e.u == 2'd2) lane_w_n = de; else begin lane_f_n = de; lbc2_n = 1'b0; end
            if (c ? rwo < now : ln < now) e_err = 1'b1;
        end
`else
        if (p_arr) begin
            if (e.u == 2'd0) begin cap = ce; ds = ce; de = ce; end
            else begin
                logic [1:0] im;  logic [15:0] dr;
                dr  = e.u == 2'd2 ? 16'd32 : 16'd4;
                cap = mx(ce, t_sh);
`ifdef QB_SEQ_CMH
                // rw = rdv ? (hitR ? cm_de : rwH) + rdl : 0: both candidates compared, hitR selects the index
`ifdef QBS_MUT_CMH
                im  = !hitR ? amax4(ce, t_sh, lane_u, !e.rdv ? 16'd0 : cm_de + 16'(e.rdl)) :   // mutant: candidates swapped
                              amax4(ce, t_sh, lane_u, !e.rdv ? 16'd0 : rwH + 16'(e.rdl));
`else
                im  = hitR ? amax4(ce, t_sh, lane_u, !e.rdv ? 16'd0 : cm_de + 16'(e.rdl)) :
                             amax4(ce, t_sh, lane_u, !e.rdv ? 16'd0 : rwH + 16'(e.rdl));
`endif
`else
                im  = amax4(ce, t_sh, lane_u, rw);
`endif
                ds  = im == 2'd0 ? ce : im == 2'd1 ? t_sh : im == 2'd2 ? lane_u : rw;
                de  = im == 2'd0 ? ce + dr : im == 2'd1 ? t_sh + dr : im == 2'd2 ? lane_u + dr : rw + dr;
                t_sh_n = de;
                if (e.u == 2'd2) lane_w_n = de; else begin lane_f_n = de; lbc2_n = e.bc2; end
            end
            t_arr_n = cap; last_v_n = 1'b1; last_pi_n = e.pi;
`ifdef QB_SEQ_CMH
            // ds = max(cap, ..) >= cap = max(ce, t_sh) (u != 0) / ce: cap < now || ds < now  <=>  cap < now
            if (ce < now && (e.u == 2'd0 || t_sh < now)) e_err = 1'b1;
`else
            if (cap < now || ds < now) e_err = 1'b1;
`endif
        end else if (p_ppu) begin
            ds = mx(ln, rw) + ((e.first && rw > ln) ? 16'(OVH) : 16'd0);
            de = ds + (e.u == 2'd2 ? 16'd32 : 16'd4);
            if (e.u == 2'd2) lane_w_n = de; else begin lane_f_n = de; lbc2_n = 1'b0; end
            if (ds < now) e_err = 1'b1;
        end
`endif
    end

    // ---------------------------------------------------------------- start phase: token of ks (parallel compares)
    // S0: no array commit in this cycle (registered state only); S1: the head of the end FIFO commits now (its cap / de
    // enter as parallel compares); s_fire = p_arr ? S1 : S0 (p_arr = a few gates after the act supply's d_eot register)
    logic S0, S1;
`ifdef QB_SEQ_TGO
    // R8a round 2 (needs QB_SEQ_CMH): the drain-length select (e.u -> ncd / lane_u mux) moves behind the compares
    // (both drain lengths compared in parallel); stamp + rdl <= ncd as the sign of ncd - stamp - rdl
    function automatic logic rwle(input logic [17:0] n);
        logic gc, gh;
        gc = $signed({n[17], n}) - $signed({3'b0, cm_de}) - $signed({14'b0, e.rdl}) >= 19'sd0;
        gh = $signed({n[17], n}) - $signed({3'b0, rwH}) - $signed({14'b0, e.rdl}) >= 19'sd0;
        return e.rdv ? (hitR ? gc : gh) : $signed(18'd0) <= $signed(n);
    endfunction
`endif
    always_comb begin
        logic [17:0] ncd;
        logic sh0, sh1, ra0, ra1;
        ncd = e.u == 2'd2 ? NC32 : NC4;
        sh0 = a.u == 2'd0 || 18'(t_sh) <= NC;
`ifdef QB_SEQ_TGO
        begin
            logic s4, s32;
`ifdef QB_SEQ_DEP
            s4  = k_ce4 && $signed({2'b0, t_sh}) <= $signed(NC4) && $signed({2'b0, lane_f}) <= $signed(NC4) && rwle(NC4);
            s32 = k_ce32 && $signed({2'b0, t_sh}) <= $signed(NC32) && $signed({2'b0, lane_w}) <= $signed(NC32) && rwle(NC32);
`else
            s4  = $signed({2'b0, ce}) <= $signed(NC4) && $signed({2'b0, t_sh}) <= $signed(NC4) &&
                  $signed({2'b0, lane_f}) <= $signed(NC4) && rwle(NC4);
            s32 = $signed({2'b0, ce}) <= $signed(NC32) && $signed({2'b0, t_sh}) <= $signed(NC32) &&
                  $signed({2'b0, lane_w}) <= $signed(NC32) && rwle(NC32);
`endif
`ifdef QBS_MUT_TGO
            sh1 = a.u == 2'd0 || (e.u == 2'd0 ? 18'(t_sh) <= NC : e.u == 2'd2 ? s4 : s32);   // mutant: drain lengths swapped
`else
            sh1 = a.u == 2'd0 || (e.u == 2'd0 ? 18'(t_sh) <= NC : e.u == 2'd2 ? s32 : s4);
`endif
        end
`else
        sh1 = a.u == 2'd0 || (e.u == 2'd0 ? 18'(t_sh) <= NC :
              ($signed({2'b0, ce}) <= $signed(ncd) && $signed({2'b0, t_sh}) <= $signed(ncd) &&
               $signed({2'b0, lane_u}) <= $signed(ncd) &&
`ifdef QB_SEQ_CMH
               (e.rdv ? (hitR ? $signed({2'b0, cm_de}) <= $signed(ncd) - $signed({13'd0, e.rdl}) :
                                $signed({2'b0, rwH}) <= $signed(ncd) - $signed({13'd0, e.rdl})) : $signed(18'd0) <= $signed(ncd))));
`else
               (e.rdv ? $signed({2'b0, rwb}) <= $signed(ncd) - $signed({13'd0, e.rdl}) : $signed(18'd0) <= $signed(ncd))));
`endif
`endif
`ifdef QB_SEQ_TGO
        // ra > x  <=>  rav && raw stamp + ral - x > 0 (one carry-save sign)
`ifdef QB_SEQ_RAL
        // ra > x  <=>  rav && raL = stamp + ral > x (raL registered with the head)
        ra0 = rok && (!((!last_v || last_pi != a.pi) && a.rav && raL > 17'(t_arr)) || rokO);
`ifdef QB_SEQ_DEP
        ra1 = rok && (!(e.pi != a.pi && a.rav && k_rce && (e.u == 2'd0 || raL > 17'(t_sh))) || rokO);
`else
        ra1 = rok && (!(e.pi != a.pi && a.rav && raL > 17'(ce) && (e.u == 2'd0 || raL > 17'(t_sh))) || rokO);
`endif
`else
        ra0 = rok && (!((!last_v || last_pi != a.pi) && a.rav &&
                        $signed({3'b0, raH}) + $signed({14'b0, a.ral}) - $signed({3'b0, t_arr}) > 19'sd0) || rokO);
        ra1 = rok && (!(e.pi != a.pi && a.rav && $signed({3'b0, raH}) + $signed({14'b0, a.ral}) - $signed({3'b0, ce}) > 19'sd0 &&
                        (e.u == 2'd0 || $signed({3'b0, raH}) + $signed({14'b0, a.ral}) - $signed({3'b0, t_sh}) > 19'sd0)) || rokO);
`endif
`else
        // ra > x  <=>  rav && raw stamp > x - ral
        ra0 = rok && (!((!last_v || last_pi != a.pi) && a.rav && $signed({2'b0, raH}) > $signed({2'b0, t_arr}) - $signed({13'd0, a.ral})) || rokO);
        ra1 = rok && (!(e.pi != a.pi && a.rav && $signed({2'b0, raH}) > $signed({2'b0, ce}) - $signed({13'd0, a.ral}) &&
                        (e.u == 2'd0 || $signed({2'b0, raH}) > $signed({2'b0, t_sh}) - $signed({13'd0, a.ral}))) || rokO);
`endif
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
`ifdef QB_SEQ_DSP
    wire        f_byp = j_push && !j_wide && fq_e && dsnow, w_byp = j_push && j_wide && wq_e && dsnow;
`ifndef SYNTHESIS
`ifndef QBS_NOCHK
    always @(posedge clk) if (rst_n && j_push && dsnow != (ds == now))
        $error("qb_seq_rt: per-candidate ds == now differs (now %0d)", now);
    always @(posedge clk) if (rst_n && (p_arr || p_ppu) && e.rdv && 17'(hitR ? cm_de : rwH) + 17'(e.rdl) > 17'h0ffff)
        $error("qb_seq_rt: drain RAW stamp + latency wraps 16 bits (now %0d)", now);
`endif
`endif
`else
    wire        f_byp = j_push && !j_wide && fq_e && ds == now, w_byp = j_push && j_wide && wq_e && ds == now;
`endif
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
`ifdef QB_SEQ_LPS
        logic [LTW-1:0] nx_w [4];                                        // + lt[nx_lb + 3] (-> wD at a pass start)
        logic [1:0]     pf_id;                                           // nx_w entry written in the previous cycle
        logic [9:0]     kN;                                              // its stamp key (= nx_w[pf_id][20:11])
`else
        logic [LTW-1:0] nx_w [3];
`endif
        logic [1:0]     pf_i;  logic [2:0] pf_age;  logic [4:0] ppn_q;
        wire  [4:0]     ppn = pp[c] < n_pq[c] ? pp[c][4:0] : 5'd0;
`ifdef QB_SEQ_NXW
        // R8a round 3 (needs QB_SEQ_LPS): the next-pass prefetch address nx_lb + pf_i is a register (la, formed from
        // the pass-table read that loads nx_lb and pf_i + 1), the lt read starts at a register
        logic [9:0]     la;
`endif
        always_ff @(posedge clk or negedge rst_n)
`ifdef QB_SEQ_NXW
            if (!rst_n) begin pf_i <= '0; pf_id <= '0; pf_age <= '0; ppn_q <= '0; nx_lb <= '0; la <= '0; end
`elsif QB_SEQ_LPS
            if (!rst_n) begin pf_i <= '0; pf_id <= '0; pf_age <= '0; ppn_q <= '0; end
`else
            if (!rst_n) begin pf_i <= '0; pf_age <= '0; ppn_q <= '0; end
`endif
            else begin
                logic [95:0] q;
`ifdef QB_SEQ_NXW
                logic [1:0]  pn;
`endif
                q = pt[nx_pi];
                nx_pi <= pq[c][ppn];
                nx_lb <= q[78:69]; nx_lc <= q[88:79]; nx_i8 <= q[20]; nx_cf <= q[3:0];
`ifdef QB_SEQ_NXW
`ifdef QBS_MUT_NXW
                la <= q[78:69] + 10'(pf_i);                              // mutant: address one entry behind
`else
                pn = pf_i + 2'd1;                                        // 2-b wrap (period 4)
                la <= q[78:69] + 10'(pn);                                // = nx_lb + pf_i of the next cycle
`endif
                nx_w[pf_i] <= lt[la];
`else
                nx_w[pf_i] <= lt[nx_lb + 10'(pf_i)];
`endif
`ifdef QB_SEQ_LPS
                pf_i <= pf_i + 2'd1;                                     // period 4 (>= 6-cycle settle still covers it)
                pf_id <= pf_i;
`ifdef QB_SEQ_NXW
                kN <= lt[la][20:11];
`else
                kN <= lt[nx_lb + 10'(pf_i)][20:11];
`endif
`else
                pf_i <= pf_i == 2'd2 ? 2'd0 : pf_i + 2'd1;
`endif
                ppn_q <= ppn;
                pf_age <= (ppn != ppn_q || wpg || (h_we && h_sel == 4'd3)) ? 3'd0 : (pf_age == 3'd7 ? 3'd7 : pf_age + 3'd1);
            end
        assign pf_ok[c] = pf_age >= 3'd6;
`ifdef QB_SEQ_NXW
`ifndef SYNTHESIS
`ifndef QBS_NOCHK
        logic la_v = 1'b0;
        always @(posedge clk) begin
            if (rst_n) la_v <= 1'b1;
            if (rst_n && la_v && la != nx_lb + 10'(pf_i))
                $error("qb_seq_rt: registered next-pass prefetch address differs on context %0d (now %0d)", c, now);
        end
`endif
`endif
`endif
        wire [9:0]  pos = c ? l_pos1 : l_pos0;
        wire        adv = AinL && EA <= {2'b0, pos} && (!i8r || RdA);
        wire [1:0]  qs_ = cfr == 4'd8 ? 2'd0 : cfr == 4'd9 ? 2'd1 : 2'd2;
        assign l_ok[c] = cval[c] && !p_fire[c] && (adv ? (BinL && EB > {2'b0, pos} && RdB) : (AinL && EA > {2'b0, pos} && RdA)) &&
                         (!i8r || fl_quiet[qs_]);
        assign lseq[c] = 16'(adv ? wB[LTW-1:26] : wA[LTW-1:26]);
        // lookups for the next cycle (address muxed to the prefetched entries at a pass start)
`ifdef QB_SEQ_LPS
        // R8a: stamp registers SX = {svb, stb}[key of window entry X] of the table in this cycle (the pending write
        // cm is bypassed at use, as lst / lsv); kept by snooping the commits, a slot entering the window takes its
        // neighbour's register or one table read at a register address (wD = lt[lp3] prefetched -> new wC; the
        // next-pass entries SN[i] re-read the cycle after each nx_w[i] write).  Readiness = compare after registers.
        logic [16:0]    SA, SB, SC, SN [3];
        logic [LTW-1:0] wD;  logic [9:0] lp4;                            // wD = lt[lp3] of this cycle, lp4 = lp3 + 1
        function automatic logic [16:0] snp(input logic [9:0] k, input logic [16:0] x);   // x of the next cycle
`ifdef QBS_MUT_LPS
            return x;                                                    // mutant: commits not snooped
`else
            return (cm_v && cm_k == k) ? {1'b1, cm_de} : x;
`endif
        endfunction
        function automatic logic rds(input logic [LTW-1:0] w, input logic [16:0] x);     // = rdn(w), x = SX
            logic hit;
            hit = cm_v && w[20:11] == cm_k;
            return !w[10] || (!go && (x[16] || hit) && le_n(hit ? cm_de : x[15:0], 6'(w[25:21])));
        endfunction
        wire        r0 = p_fire[c] ? rds(nx_w[0], SN[0]) : rds(wA, SA), r1 = p_fire[c] ? rds(nx_w[1], SN[1]) : rds(wB, SB),
                    r2 = rds(wC, SC);
        wire [9:0]  kD = wD[20:11];
        wire [16:0] tN = {svb[kN], stb[kN]}, tD = {svb[kD], stb[kD]};   // the 2 table reads (register addresses)
        wire        ltw = h_we && h_sel == 4'd10;
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) begin SA <= '0; SB <= '0; SC <= '0; for (int i = 0; i < 3; i++) SN[i] <= '0; end
            else begin
                logic [16:0] nA, nB, nC;
                if (!go && p_fire[c]) begin
                    nA = snp(nx_w[0][20:11], SN[0]); nB = snp(nx_w[1][20:11], SN[1]); nC = snp(nx_w[2][20:11], SN[2]);
                end else if (!go && adv) begin
                    nA = snp(wB[20:11], SB); nB = snp(wC[20:11], SC); nC = snp(kD, tD);
                end else begin
                    nA = snp(wA[20:11], SA); nB = snp(wB[20:11], SB); nC = snp(wC[20:11], SC);
                end
                SA <= {nA[16] && !go, nA[15:0]}; SB <= {nB[16] && !go, nB[15:0]}; SC <= {nC[16] && !go, nC[15:0]};
                for (int i = 0; i < 3; i++) begin
                    logic [16:0] n;
                    n = snp(nx_w[i][20:11], pf_id == 2'(i) ? tN : SN[i]);
                    SN[i] <= {n[16] && !go, n[15:0]};
                end
            end
        // wD = lt[lp3] (lt writes of this cycle bypassed); wC takes it at an advance
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) lp4 <= 10'd4;
            else if (!go && p_fire[c]) begin
                lp4 <= nx_lb + 10'd4;
                wD <= (ltw && h_addr == nx_lb + 10'd3) ? h_d[LTW-1:0] : nx_w[3];
            end else if (!go && adv) begin
                lp4 <= lp4 + 10'd1;
                wD <= (ltw && h_addr == lp4) ? h_d[LTW-1:0] : lt[lp4];
            end else if (ltw && h_addr == lp3) wD <= h_d[LTW-1:0];
`ifndef SYNTHESIS
`ifndef QBS_NOCHK
        wire r0o = rdn(p_fire[c] ? nx_w[0] : wA), r1o = rdn(p_fire[c] ? nx_w[1] : wB), r2o = rdn(wC);
        always @(posedge clk) if (rst_n && !(p_fire[c] && !pf_ok[c]) && (cval[c] || p_fire[c]) &&
                                  ({r0, r1} != {r0o, r1o} || (!p_fire[c] && r2 != r2o)))
            $error("qb_seq_rt: registered load-permission stamps differ on context %0d (now %0d): %b / %b", c, now,
                   {r0, r1, r2}, {r0o, r1o, r2o});
        always @(posedge clk) if (rst_n && !go && adv && cval[c] && !p_fire[c] && wD != lt[lp3])
            $error("qb_seq_rt: prefetched lt[lp3] differs on context %0d (now %0d)", c, now);
`endif
`endif
`else
        wire        r0 = rdn(p_fire[c] ? nx_w[0] : wA), r1 = rdn(p_fire[c] ? nx_w[1] : wB), r2 = rdn(wC);
`endif
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
`elsif QB_SEQ_LPS
                wA <= wB; wB <= wC; wC <= wD;                            // wD = lt[lp3]
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
`ifdef QB_SEQ_TKS
            if (run && tk_err) err <= 1'b1;
`endif
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

// R8d QB_SEQ_DEP: one candidate sum per instance (see qb_seq_rt k_*)
module qbs_add3 (input logic [15:0] a, b, c, output logic [15:0] s);
    assign s = a + b + c;
endmodule
