// qb_seq: image-independent sequencer of qb_top (R3b, qb_top R3B = 1).  One descriptor program per network (host
// loaded once): the compiler's static issue order (compile/static_seq.py), one 80-b descriptor per tile in commit order.
// Runtime gating replaces R3a's per-image time schedule:
//   * stamp table (one entry per committed tile: time its writes are done = drain end de, pecmp: capture; valid bit
//     cleared at go) = the RAW / position scoreboard: a consumer waits for stamp[dep] + lat of the producer tile its
//     hazard binds to (rasdep: array reads, rdsdep: drain-time reads; both static pointers of the descriptor);
//   * in-order commit engine (end pointer ke): array tile k ends at its ce (d_vld & d_eot of the act supply = last item
//     + 1): cap = max(ce, t_sh), ds = max(cap, lane, rw), de = ds + drain (4 fused / 32 wide; pecmp: cap = ds = de =
//     ce); PPU-only tiles (hm) end when reached: ds = max(lane + bub, rw) (+ OVH first tile of the pass if rw > lane
//     + bub); one tile per cycle; capture / PPU job events fire at cap / ds (bypass when due in the same cycle);
//   * tile tokens (start pointer ks over array tiles): token of array tile k in the first cycle with: previous array
//     tile ended, now >= t_arr, now >= ra (+ OVH at a pass switch if ra > t_arr), drained tiles now + C >= t_sh
//     (just-in-time start: capture when the shadow frees); C = chunk items (static) or, block 6, executed slices =
//     popcount of the writer-side flags (final before ra);
//   * act-supply contexts: static per-context pass list, next pass started the cycle after the context's done pulse;
//     load permissions per pass from static entries (pos, rasdep, raslat, seq): binary pos = virtual rows, int8 pos =
//     (j + 1) x executed S words per channel tile (from the flags); l_ok = entry beyond the loader + stamp ready.
// All times are the model's (compile/cycles.list_schedule with the `order` hook): the RTL is cycle-exact against it.
module qb_seq #(parameter int NT = 1024, parameter int OVH = 12) (
    input  logic         clk, rst_n, go, run,
    input  logic [15:0]  now,
    input  logic         h_we,
    input  logic [3:0]   h_sel,                   // 4 / 5 pass list ctx 0 / 1, 10 LT, 11 descriptors, 15 counts
    input  logic [9:0]   h_addr,
    input  logic [95:0]  h_d,
    input  logic [95:0]  pt [32],
    // act supply
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
    // events
    output logic         c_fire, c_cmp,
    output logic [4:0]   c_pi,
    output logic [6:0]   c_tp,
    output logic [3:0]   c_ct,
    output logic         f_fire,
    output logic [15:0]  f_job,                   // {ct[3:0], tp[6:0], pi[4:0]} (R3a fq layout)
    output logic         w_fire,
    output logic [15:0]  w_job,
    output logic         err
);
    // ---------------------------------------------------------------- program memories
    logic [79:0] dsc [NT];
    logic [41:0] lt [1024];
    logic [4:0]  pq [2][32];
    logic [5:0]  n_pq [2];
    logic [9:0]  nt, ks0;
    always_ff @(posedge clk)
        if (h_we) unique case (h_sel)
            4'd4:  pq[0][h_addr[4:0]] <= h_d[4:0];
            4'd5:  pq[1][h_addr[4:0]] <= h_d[4:0];
            4'd10: lt[h_addr] <= h_d[41:0];
            4'd11: dsc[h_addr] <= h_d[79:0];
            4'd15: unique case (h_addr[3:0])
                       4'd0: n_pq[0] <= h_d[5:0];
                       4'd1: n_pq[1] <= h_d[5:0];
                       4'd6: ks0 <= h_d[9:0];
                       4'd7: nt <= h_d[9:0];
                       default: ;
                   endcase
            default: ;
        endcase
    typedef struct packed {
        logic       nxv;  logic [9:0] nxa;                              // [73:63] next array tile
        logic [4:0] rdl;  logic [9:0] rdk;  logic rdv;                  // [62:47] rds dep
        logic [4:0] ral;  logic [9:0] rak;  logic rav;                  // [46:31] ras dep
        logic [1:0] i8;   logic [5:0] C;                                // [30:23]
        logic first, hm, bc2, ctx;  logic [1:0] u;  logic arr;          // [22:16] u: 0 pecmp 1 fused 2 wide
        logic [3:0] ct;   logic [6:0] tp;  logic [4:0] pi;              // [15:0]
    } dsc_t;
    function automatic dsc_t dget(input logic [79:0] w); return dsc_t'(w[73:0]); endfunction
    function automatic logic [15:0] mx(input logic [15:0] a, b); return a > b ? a : b; endfunction

    // ---------------------------------------------------------------- stamp table (scoreboard)
    logic [15:0] stamp [NT];
    logic [NT-1:0] sv;

    // ---------------------------------------------------------------- engine state
    logic [9:0]  ke, ks, kprev;
    logic        ksv, kpv, ce_p, last_v, lbc2;
    logic [15:0] ce_q, t_arr, t_sh, lane_f, lane_w;
    logic [4:0]  last_pi;
    // events
    logic        cp_v;  logic [15:0] cp_t;  logic cp_cmp;  logic [4:0] cp_pi;  logic [6:0] cp_tp;  logic [3:0] cp_ct;
    localparam int FD = 32, WD = 8;
    logic [31:0] fq [FD];  logic [5:0] fq_w, fq_r;                      // {ds, job}
    logic [31:0] wq [WD];  logic [3:0] wq_w, wq_r;

    // ---------------------------------------------------------------- end phase (comb)
    dsc_t        e;
    logic        ce_ev, p_arr, p_ppu;
    logic [15:0] ce, rw, cap, ds, de, lane_u, ln;
    logic [15:0] t_arr_n, t_sh_n, lane_f_n, lane_w_n;
    logic        last_v_n, lbc2_n;
    logic [4:0]  last_pi_n;
    logic        e_err;
    assign ce_ev = d_vld && d_eot;
    always_comb begin
        e = dget(dsc[ke]);
        p_arr = run && ke < nt && e.arr && (ce_p || ce_ev);
        p_ppu = run && ke < nt && !e.arr;
        ce = ce_p ? ce_q : now;
        rw = e.rdv ? stamp[e.rdk] + 16'(e.rdl) : 16'd0;
`ifdef QBT_MUT_RDS
        rw = 16'd0;                                                      // mutant: drain-read RAW (rds) scoreboard ignored
`endif
        lane_u = e.u == 2'd2 ? lane_w : lane_f;
        ln = lane_u + 16'(lbc2 && e.hm && e.u == 2'd1);
        cap = '0; ds = '0; de = '0;
        t_arr_n = t_arr; t_sh_n = t_sh; lane_f_n = lane_f; lane_w_n = lane_w; last_v_n = last_v; last_pi_n = last_pi;
        lbc2_n = lbc2;
        e_err = (p_arr || p_ppu) && e.rdv && !sv[e.rdk];
        if (p_arr) begin
            if (e.u == 2'd0) begin cap = ce; ds = ce; de = ce; end
            else begin
                cap = mx(ce, t_sh);
                ds  = mx(mx(cap, lane_u), rw);
                de  = ds + (e.u == 2'd2 ? 16'd32 : 16'd4);
                t_sh_n = de;
                if (e.u == 2'd2) lane_w_n = de; else begin lane_f_n = de; lbc2_n = e.bc2; end
            end
            t_arr_n = cap; last_v_n = 1'b1; last_pi_n = e.pi;
            if (cap < now || ds < now) e_err = 1'b1;                     // event needed before it was known
        end else if (p_ppu) begin
            ds = mx(ln, rw) + ((e.first && rw > ln) ? 16'(OVH) : 16'd0);
            de = ds + (e.u == 2'd2 ? 16'd32 : 16'd4);
            if (e.u == 2'd2) lane_w_n = de; else begin lane_f_n = de; lbc2_n = 1'b0; end
            if (ds < now) e_err = 1'b1;
        end
    end

    // ---------------------------------------------------------------- start phase (comb): tile token of ks
    dsc_t        a;
    logic        s_fire, prev_end, dep_ok;
    logic [15:0] ra, ra2;
    logic [7:0]  Cn;
    always_comb begin
        a = dget(dsc[ks]);
        prev_end = !kpv || ke > kprev || (p_arr && ke == kprev);
        dep_ok = !a.rav || sv[a.rak];
        ra = a.rav ? stamp[a.rak] + 16'(a.ral) : 16'd0;
`ifdef QBT_MUT_SB
        ra = 16'd0;                                                      // mutant: scoreboard bypassed at the token
`endif
        ra2 = ra + (((!last_v_n || last_pi_n != a.pi) && ra > t_arr_n) ? 16'(OVH) : 16'd0);
        unique case (a.i8)
            2'd1: Cn = 8'($countones(fs_hq));
            2'd2: Cn = 8'($countones(fs_hqd));
            2'd3: Cn = 8'($countones(fs_z));
            default: Cn = 8'(a.C);
        endcase
        s_fire = run && ksv && prev_end && dep_ok && now >= t_arr_n && now >= ra2 &&
                 (a.u == 2'd0 || 17'(now) + 17'(Cn) >= 17'(t_sh_n));
        tgo = s_fire ? (a.ctx ? 2'b10 : 2'b01) : 2'b00;
    end

    // ---------------------------------------------------------------- capture event (at most one pending)
    always_comb begin
        c_fire = 1'b0; c_cmp = 1'b0; c_pi = '0; c_tp = '0; c_ct = '0;
        if (cp_v && cp_t == now) begin c_fire = 1'b1; c_cmp = cp_cmp; c_pi = cp_pi; c_tp = cp_tp; c_ct = cp_ct; end
        else if (p_arr && cap == now) begin c_fire = 1'b1; c_cmp = e.u == 2'd0; c_pi = e.pi; c_tp = e.tp; c_ct = e.ct; end
    end
    // ---------------------------------------------------------------- PPU job queues (in commit order, ds monotonic)
    wire        j_push = (p_arr && e.u != 2'd0) || p_ppu;
    wire        j_wide = e.u == 2'd2;
    wire [15:0] j_job = {e.ct, e.tp, e.pi};
    wire        fq_e = fq_w == fq_r, wq_e = wq_w == wq_r;
    wire [31:0] fh = fq[fq_r[4:0]], wh = wq[wq_r[2:0]];
    wire        f_head = !fq_e && fh[31:16] == now, w_head = !wq_e && wh[31:16] == now;
    wire        f_byp = j_push && !j_wide && fq_e && ds == now, w_byp = j_push && j_wide && wq_e && ds == now;
    assign f_fire = f_head || f_byp;
    assign f_job  = f_head ? fh[15:0] : j_job;
    assign w_fire = w_head || w_byp;
    assign w_job  = w_head ? wh[15:0] : j_job;

    // ---------------------------------------------------------------- pass starts
    logic [5:0] pp [2];
    logic [1:0] done_q;
    for (genvar c = 0; c < 2; c++) begin : g_ps
        assign p_fire[c] = run && pp[c] < n_pq[c] && (pp[c] == '0 ? now == 16'd0 : done_q[c]);
        assign p_pi[c] = pq[c][pp[c][4:0]];
    end

    // ---------------------------------------------------------------- load permissions
    logic [1:0] cval;  logic [4:0] cpi [2];  logic [9:0] lptr [2], lend [2], lbse [2];
    logic [10:0] nw_hq, nw_hqd, nw_z;
    always_comb begin
        logic [31:0] zq;
        for (int i = 0; i < 32; i++) zq[i] = |fs_z[4 * i +: 4];
        nw_hq = 11'($countones(fs_hq)); nw_hqd = 11'(2 * $countones(fs_hqd)); nw_z = 11'($countones(zq));
    end
    logic [15:0] lseq [2];
    for (genvar c = 0; c < 2; c++) begin : g_lp
        wire [95:0] pw_ = pt[cpi[c]];
        wire        i8 = pw_[20];
        wire [3:0]  cf = pw_[3:0];
        wire [10:0] nw = cf == 4'd8 ? nw_hq : cf == 4'd9 ? nw_hqd : nw_z;
        wire [9:0]  pos = c ? l_pos1 : l_pos0;
        function automatic logic [11:0] epos(input logic [9:0] j, input logic [41:0] w, input logic [9:0] lb,
                                             input logic i8_, input logic [10:0] nw_);
            return i8_ ? 12'((j - lb + 10'd1) * nw_) : {2'b0, w[9:0]};
        endfunction
        function automatic logic erdy(input logic [41:0] w);
            return !w[10] || (sv[w[20:11]] && now >= stamp[w[20:11]] + 16'(w[25:21]));
        endfunction
        wire [41:0] e0 = lt[lptr[c]];
        wire        adv = lptr[c] < lend[c] && epos(lptr[c], e0, lbse[c], i8, nw) <= {2'b0, pos} && (!i8 || erdy(e0));
        wire [9:0]  cur = adv ? lptr[c] + 10'd1 : lptr[c];
        wire [41:0] e1 = lt[cur];
`ifdef QBT_MUT_LOK
        wire        rdy1 = 1'b1;                                         // mutant: load permission without the scoreboard
`else
        wire        rdy1 = erdy(e1);
`endif
        assign l_ok[c] = cval[c] && !p_fire[c] && cur < lend[c] && epos(cur, e1, lbse[c], i8, nw) > {2'b0, pos} && rdy1 &&
                         (!i8 || fl_quiet[cf == 4'd8 ? 0 : cf == 4'd9 ? 1 : 2]);
        assign lseq[c] = e1[41:26];
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) begin cval[c] <= 1'b0; cpi[c] <= '0; lptr[c] <= '0; lend[c] <= '0; lbse[c] <= '0; end
            else if (go) cval[c] <= 1'b0;
            else if (p_fire[c]) begin
                logic [95:0] q;
                q = pt[p_pi[c]];
                cval[c] <= 1'b1; cpi[c] <= p_pi[c]; lptr[c] <= q[78:69]; lbse[c] <= q[78:69]; lend[c] <= q[78:69] + q[88:79];
            end else lptr[c] <= cur;
    end
    assign l_seq0 = lseq[0];
    assign l_seq1 = lseq[1];

    // ---------------------------------------------------------------- state update
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            ke <= '0; ks <= '0; kprev <= '0; ksv <= 1'b0; kpv <= 1'b0; ce_p <= 1'b0; ce_q <= '0; last_v <= 1'b0;
            last_pi <= '0; lbc2 <= 1'b0; t_arr <= '0; t_sh <= '0; lane_f <= '0; lane_w <= '0; sv <= '0; cp_v <= 1'b0;
            fq_w <= '0; fq_r <= '0; wq_w <= '0; wq_r <= '0; pp[0] <= '0; pp[1] <= '0; done_q <= '0; err <= 1'b0;
        end else if (go) begin
            ke <= '0; ks <= ks0; kprev <= '0; ksv <= 1'b1; kpv <= 1'b0; ce_p <= 1'b0; last_v <= 1'b0; lbc2 <= 1'b0;
            t_arr <= '0; t_sh <= '0; lane_f <= '0; lane_w <= '0; sv <= '0; cp_v <= 1'b0;
            fq_w <= '0; fq_r <= '0; wq_w <= '0; wq_r <= '0; pp[0] <= '0; pp[1] <= '0; done_q <= '0; err <= 1'b0;
        end else begin
            done_q <= done;
            for (int c = 0; c < 2; c++) if (p_fire[c]) pp[c] <= pp[c] + 6'd1;
            // end phase
            t_arr <= t_arr_n; t_sh <= t_sh_n; lane_f <= lane_f_n; lane_w <= lane_w_n; last_v <= last_v_n;
            last_pi <= last_pi_n; lbc2 <= lbc2_n;
            if (p_arr || p_ppu) begin
                ke <= ke + 10'd1;
                stamp[ke] <= de;
                sv[ke] <= 1'b1;
            end
            if (p_arr) ce_p <= 1'b0;
            if (ce_ev && !(p_arr && !ce_p)) begin
                if (ce_p) err <= 1'b1;                                   // two tile ends pending
                ce_p <= 1'b1; ce_q <= now;
            end
            // capture event
            if (cp_v && cp_t == now) cp_v <= 1'b0;
            if (p_arr && cap != now) begin
                if (cp_v && cp_t != now) err <= 1'b1;
                cp_v <= 1'b1; cp_t <= cap; cp_cmp <= e.u == 2'd0; cp_pi <= e.pi; cp_tp <= e.tp; cp_ct <= e.ct;
            end
            if (cp_v && cp_t < now) err <= 1'b1;
            // job queues
            if (f_head) fq_r <= fq_r + 6'd1;
            if (w_head) wq_r <= wq_r + 4'd1;
            if (j_push && !j_wide && !f_byp) begin fq[fq_w[4:0]] <= {ds, j_job}; fq_w <= fq_w + 6'd1; end
            if (j_push && j_wide && !w_byp) begin wq[wq_w[2:0]] <= {ds, j_job}; wq_w <= wq_w + 4'd1; end
            if ((f_head && f_byp) || (w_head && w_byp) || (!fq_e && fh[31:16] < now) || (!wq_e && wh[31:16] < now) ||
                fq_w - fq_r > 6'(FD - 1) || wq_w - wq_r > 4'(WD - 1)) err <= 1'b1;
            if (e_err) err <= 1'b1;
            // start phase
            if (s_fire) begin ks <= a.nxa; ksv <= a.nxv; kprev <= ks; kpv <= 1'b1; end
        end
endmodule

// qb_prm: params path (R3b).  Bank of NM = 9 behavioural rf_sp 240 x 144 (mux 2) macros read in parallel: one row =
// 1296 b; a (pass, ct) set occupies 4 rows (fused pf 64 x 81 b = 5184 b, wide pw 64 x 79 b = 5056 b) or 1 row (T2 64 x
// 17 b = 1088 b); the per-pass common bits (pf 5, pw 3) come from the pass table.  Three consumers with staging
// registers (= the macro output registers): fused (2 sets, double-buffered), wide (1), T2 (1).  Static fetch lists
// (host loaded) give each consumer's sets in use order {nuse, base row, tag}; a consumer's next set is fetched as soon
// as a staging register is free (its previous set's last use 2 cycles ahead, seen at stage D of the step delay line),
// one row per cycle, priority T2 > fused > wide.  Request in x -> address register -> macro -> staging register valid
// in x + 3.  Uses (stage D + 2) check the staging register is valid and holds the job's (pass, ct) (err otherwise).
module qb_prm #(parameter int NM = 9, parameter int MW = 144, parameter int DEP = 240) (
    input  logic         clk, rst_n, go,
    input  logic         h_we,
    input  logic [3:0]   h_sel,                   // 1 bank row, 12 / 13 / 14 fetch list f / w / t, 15 counts (8..10)
    input  logic [9:0]   h_addr,
    input  logic [NM*MW-1:0] h_d,
    // uses: early (stage D, last use of a set 2 cycles ahead) and actual (stage D + 2), with the job's tag {ct, pi}
    input  logic [2:0]   u_early,                 // {t, w, f}
    input  logic [2:0]   u_use,
    input  logic [8:0]   tag_f, tag_w, tag_t,
    output logic [5183:0] pf,
    output logic [5055:0] pw,
    output logic [1087:0] t2,
    output logic         err
);
    localparam int RW = NM * MW;                       // 1296
    localparam int NR [3] = '{4, 4, 1};                // rows per set: f, w, t
`ifdef QBT_MUT_PRM1
    localparam int NB [3] = '{1, 1, 1};                // mutant: fused consumer single-buffered
`else
    localparam int NB [3] = '{2, 1, 1};                // staging registers
`endif
    logic [24:0] fl [3][256];                          // {nuse[7:0], base[7:0], tag[8:0]}
    logic [7:0]  nfl [3];
    always_ff @(posedge clk)
        if (h_we) begin
            if (h_sel == 4'd12) fl[0][h_addr[7:0]] <= h_d[24:0];
            if (h_sel == 4'd13) fl[1][h_addr[7:0]] <= h_d[24:0];
            if (h_sel == 4'd14) fl[2][h_addr[7:0]] <= h_d[24:0];
            if (h_sel == 4'd15 && h_addr[3:0] >= 4'd8 && h_addr[3:0] <= 4'd10) nfl[h_addr[3:0] - 4'd8] <= h_d[7:0];
        end
    // ---- bank
    logic        b_ren;  logic [7:0] b_a;  logic [RW-1:0] b_q;
    for (genvar m = 0; m < NM; m++) begin : g_pm
        qbt_rfsp #(MW, DEP) u_m (.clk, .ren(b_ren), .we(h_we && h_sel == 4'd1), .a(h_we ? h_addr[7:0] : b_a),
                                 .wd(h_d[MW*m +: MW]), .q(b_q[MW*m +: MW]));
    end
    // ---- per consumer state
    logic [7:0] rf [3], rfree [3], ruse [3], uf [3], uu [3];
    logic [2:0] rowc [3];
    logic [RW*4-1:0] stg_f [2];
    logic [RW*4-1:0] stg_w;
    logic [RW-1:0]   stg_t;
    logic [1:0] vf;  logic vw, vt;
    logic [8:0] tgf [2];  logic [8:0] tgw, tgt;
    // ---- arbiter (comb): T2 > fused > wide
    logic [2:0] want;  logic [1:0] gsel;  logic gnt;
    always_comb begin
        for (int c = 0; c < 3; c++) want[c] = rf[c] < nfl[c] && rf[c] < rfree[c] + 8'(NB[c]);
        gnt = |want;
        gsel = want[2] ? 2'd2 : want[0] ? 2'd0 : 2'd1;
    end
    // request pipeline: x arbiter -> (b_a, tags) registers -> macro q in x + 2 -> staging write at end of x + 2
    logic       p1_v, p2_v;  logic [1:0] p1_c, p2_c;  logic [2:0] p1_r, p2_r;  logic p1_b, p2_b, p1_l, p2_l;
    logic [8:0] p1_t, p2_t;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            p1_v <= 1'b0; p2_v <= 1'b0; b_ren <= 1'b0; err <= 1'b0; vf <= '0; vw <= 1'b0; vt <= 1'b0;
            for (int c = 0; c < 3; c++) begin rf[c] <= '0; rfree[c] <= '0; ruse[c] <= '0; uf[c] <= '0; uu[c] <= '0; rowc[c] <= '0; end
        end else if (go) begin
            p1_v <= 1'b0; p2_v <= 1'b0; b_ren <= 1'b0; err <= 1'b0; vf <= '0; vw <= 1'b0; vt <= 1'b0;
            for (int c = 0; c < 3; c++) begin rf[c] <= '0; rfree[c] <= '0; ruse[c] <= '0; uf[c] <= '0; uu[c] <= '0; rowc[c] <= '0; end
        end else begin
            logic [24:0] w;
            // request
            b_ren <= gnt;
            p1_v <= gnt;
            if (gnt) begin
                w = fl[gsel][rf[gsel]];
                b_a  <= w[16:9] + 8'(rowc[gsel]);
                p1_c <= gsel; p1_r <= rowc[gsel]; p1_b <= rf[gsel][0]; p1_t <= w[8:0];
                p1_l <= rowc[gsel] == 3'(NR[gsel] - 1);
                if (rowc[gsel] == 3'(NR[gsel] - 1)) begin rowc[gsel] <= '0; rf[gsel] <= rf[gsel] + 8'd1; end
                else rowc[gsel] <= rowc[gsel] + 3'd1;
            end
            p2_v <= p1_v; p2_c <= p1_c; p2_r <= p1_r; p2_b <= p1_b; p2_l <= p1_l; p2_t <= p1_t;
            // landing (macro q valid this cycle for the request of x = now - 2)
            if (p2_v) unique case (p2_c)
                2'd0: begin
`ifdef QBT_MUT_PRMR
                    stg_f[p2_b][RW * (p2_r ^ 3'd1) +: RW] <= b_q;           // mutant: rows of a fused set swapped
`else
                    stg_f[p2_b][RW * p2_r +: RW] <= b_q;
`endif
                    if (p2_l) begin vf[p2_b] <= 1'b1; tgf[p2_b] <= p2_t; end
                end
                2'd1: begin stg_w[RW * p2_r +: RW] <= b_q; if (p2_l) begin vw <= 1'b1; tgw <= p2_t; end end
                default: begin stg_t <= b_q; vt <= 1'b1; tgt <= p2_t; end
            endcase
            // early uses: free a staging register 2 cycles ahead of the set's last use
            for (int c = 0; c < 3; c++)
                if (u_early[c]) begin
                    w = fl[c][rfree[c]];
                    if (uf[c] + 8'd1 == w[24:17]) begin uf[c] <= '0; rfree[c] <= rfree[c] + 8'd1; end
                    else uf[c] <= uf[c] + 8'd1;
                end
            // actual uses: check, retire the set after its last use
            for (int c = 0; c < 3; c++)
                if (u_use[c]) begin
                    logic ok;
                    w = fl[c][ruse[c]];
                    ok = c == 0 ? (vf[ruse[0][0]] && tgf[ruse[0][0]] == tag_f) : c == 1 ? (vw && tgw == tag_w) : (vt && tgt == tag_t);
                    if (!ok) err <= 1'b1;
                    if (uu[c] + 8'd1 == w[24:17]) begin
                        uu[c] <= '0; ruse[c] <= ruse[c] + 8'd1;
                        if (c == 0) vf[ruse[0][0]] <= 1'b0; else if (c == 1) vw <= 1'b0; else vt <= 1'b0;
                    end else uu[c] <= uu[c] + 8'd1;
                end
            // a landing must not hit a register still in use (would need its set's last use behind it)
            if (p2_v && p2_c == 2'd0 && vf[p2_b] && p2_r == 3'd0) err <= 1'b1;
            if (p2_v && p2_c == 2'd1 && vw && p2_r == 3'd0) err <= 1'b1;
            if (p2_v && p2_c == 2'd2 && vt) err <= 1'b1;
        end
    assign pf = stg_f[ruse[0][0]];
    assign pw = stg_w[5055:0];
    assign t2 = stg_t[1087:0];
endmodule
