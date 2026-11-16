// qb_head: head of QC18B-ACC (R3c; ARCH.md "Head", results/r3c.md): global pool + int8 FC, image to logits.
// Exact integer semantics of golden_p2.IntBin2 (qc18b/int_bin.py IntBin.forward):
//   pq[c]  = requant(sum_{16 px} relu(s7[px, c]), pool_m0, pool_sh, 0, 127)          (c = 0..511)
//   lg[j]  = sum_c pq[c] W8[j, c] + fbq[j]                                             (j = 0..99, int32)
//   (IntBin2 logits = lg x fscale in fp64, a per-class scale outside the integer datapath: host side.)
//
// Pool (no S re-read, no extra cycles on the image): taps the fused write-back bus of the last pass (b7.c2: 8 tiles =
//   8 channel tiles x 16 px, 4 drain steps of 4 px x 64 ch) at the cycle its S write is requested:
//   per channel s4 = sum of relu over the 4 px of the step, tile accumulator tacc[64] (19 b) cleared at step 0; at step
//   3 the 64 complete sums go to a hold register and NQ = 4 requant lanes (qbcw_lane of qb_core.sv, omode u8, m = pool
//   m0, sh = pool sh, no bias / ReLU / r) convert them in 16 cycles (b7.c2 tiles are >= 16 cycles apart: 16 chunk
//   items) into pq (512 x 7 b register).  After the 512th pq write: pool done -> FC start.
// FC: one class at a time, 32 int8 MACs / cycle over 16 chunk rows; FC macro = behavioural rf_sp 408 x 64 (mux 4),
//   4 lanes x 4 deep = 1 632 rows x 256 b (results/mem.md e_fc shape, 16 macros), registered boundaries (request x ->
//   address register -> macro -> output register, row data in x + 3).  Row layout (hw/tb/export_top3.py): per group
//   of 8 classes one bias row (8 x int32) then 8 x 16 weight rows; 1 613 rows = 1 613 cycles + 5 pipeline.
//   Stage x + 3: bias row -> breg, or 32 products pq[32 m + n] x W8 (7 b x 8 b) + adder tree -> psum (20 b), stage
//   x + 4: acc = (m == 0 ? bias : acc) + psum; class out (lo_vld / lo_idx / lo_val) in x + 5 for m = 15.
// Overlap: the FC of image i runs while image i + 1 computes; the head's only state shared between images is pq
//   (written by image i + 1's last pass, read by FC i): err if a pq write or a pool done meets a busy FC.
// R4b hook HP (default 0 = as above): the FC adder tree in two stages at the same cycles: the pq chunk of a row is
//   selected one stage early (from fm[2]; pq is stable while the FC runs: a pq write during the FC is err) into xs, and
//   the 32 products form two 16-product partial sums (registered) that the accumulate stage adds (3-input add).
// R5e parameter FW (FC weight port, b / cycle; default 256 = everything above unchanged).  FW = 128 (results/r5e_fc.md):
//   16 int8 MACs / cycle over 32 chunk rows per class; rows of 128 b: per group of G = 4 classes one bias row
//   (4 x int32) then 4 x 32 weight rows (3 225 rows); FC macro = ONE behavioural rf_sp 3232 x 128 (the ARM
//   sram_sp_adv 3232 x 128 mux 8, qb_f_3232x128m8), same registered boundaries (row in x + 3); 12-b row address
//   (qb_chip: h_sel 16 rows 0..2047, h_sel 18 rows 2048..).  HP: two partial sums of NMAC / 2 products.
// R7g parameter PCOL (qb_chip define QB_HEAD_PCOL, default 0 = everything above unchanged): the pool split into 8
//   column slices g_pcol[c].u_pc (qb_hpcol): slice c takes only column c's f_y lanes (64 q + 8 c + i: 4 px x 8 ch x
//   16 b) and holds s4 / tacc / hold of its 8 channels; requant lane i reads hold[NQ rq_j + i] = channel of column
//   (NQ rq_j) / 8: each slice drives its NQ x 19-b candidate only when rq_j selects it (else 0) and the lanes take the
//   OR of the 8 slice outputs.  Control (tap, rq_v / rq_j / hct / rq_ovr / err) stays here: same cycles, same values.
module qb_head #(parameter int NQ = 4, parameter int NK = 512, parameter int FW = 256,
                 parameter int NFR = (FW == 128 ? 3232 : 1632), parameter bit HP = 0, parameter bit PCOL = 0,
                 parameter int AW = (FW == 128 ? 12 : 11)) (
    input  logic          clk, rst_n,
    // host: FC macro rows (fc_we) at h_addr
    input  logic          fc_we,
    input  logic [AW-1:0] h_addr,
    input  logic [FW-1:0] h_d,
    // configuration (qb_chip registers)
    input  logic [30:0]   c_m0,
    input  logic [5:0]    c_sh,
    input  logic [4:0]    c_last,
    input  logic [6:0]    c_ncls,
    input  logic [AW-1:0] c_nrows,
    // fused write-back bus of qb_top (qb_top dbg_f* taps: f_y / tags at the S write request)
    input  logic          f_v,
    input  logic [4:0]    f_pi,
    input  logic [3:0]    f_ct,
    input  logic [1:0]    f_k,
    input  logic [4351:0] f_y,
    // logits out
    output logic          lo_vld,
    output logic [6:0]    lo_idx,
    output logic [31:0]   lo_val,
    output logic          pool_done, fc_busy, busy, err
);
    // ================================================================ pool: tile accumulators
    wire tap = f_v && f_pi == c_last;
    logic [18:0] s4 [64];
    always_comb
        for (int c = 0; c < 64; c++) begin
            s4[c] = '0;
            if (!PCOL)
            for (int q = 0; q < 4; q++) begin
                logic signed [15:0] v;
                v = f_y[17 * (64 * q + c) +: 16];
`ifdef QBH_MUT_RELU
                s4[c] = s4[c] + 19'(v);                                   // mutant: no ReLU in the pool sum
`else
                s4[c] = s4[c] + ((v < 0) ? 19'd0 : 19'(v));
`endif
            end
        end
    logic [18:0] tacc [64], hold [64];
    logic [3:0]  hct, rq_j;
    logic        rq_v, rq_ovr;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin rq_v <= 1'b0; rq_j <= '0; rq_ovr <= 1'b0; end
        else begin
            if (tap && !PCOL) for (int c = 0; c < 64; c++) tacc[c] <= (f_k == 2'd0 ? 19'd0 : tacc[c]) + s4[c];
            if (tap && f_k == 2'd3) begin
                if (!PCOL) for (int c = 0; c < 64; c++) hold[c] <= tacc[c] + s4[c];
                hct <= f_ct; rq_v <= 1'b1; rq_j <= '0;
                if (rq_v && rq_j != 4'd15) rq_ovr <= 1'b1;                // a tile completed before the last was converted
            end else if (rq_v) begin
                rq_j <= rq_j + 4'd1;
                if (rq_j == 4'd15) rq_v <= 1'b0;
            end
        end
    // ================================================================ PCOL: column slices + select
    logic [NQ*19-1:0] pc_o [8];
    logic [18:0]      pc_q [NQ];                                         // OR of the slice candidates = lane inputs
    for (genvar c = 0; c < (PCOL ? 8 : 0); c++) begin : g_pcol
        logic [511:0] fyc;                                              // column c: f_y lane 64 q + 8 c + i, 16 b
        for (genvar q = 0; q < 4; q++) begin : g_fq
            for (genvar i = 0; i < 8; i++) begin : g_fi
                assign fyc[16 * (8 * q + i) +: 16] = f_y[17 * (64 * q + 8 * c + i) +: 16];
            end
        end
        qb_hpcol #(.NQ(NQ), .C(c)) u_pc (.clk, .rst_n, .tap, .k0(f_k == 2'd0), .k3(f_k == 2'd3), .fy(fyc), .rq_j,
                                         .po(pc_o[c]));
    end
    always_comb
        for (int i = 0; i < NQ; i++) begin
            pc_q[i] = '0;
            if (PCOL) for (int c = 0; c < 8; c++) pc_q[i] = pc_q[i] | pc_o[c][19 * i +: 19];
        end
    // ================================================================ pool requant lanes (latency 4)
    logic [NQ-1:0]  qv;
    logic [18:0]    qy [NQ];
    for (genvar i = 0; i < NQ; i++) begin : g_q
        logic b_unused;
        qbcw_lane #(.TP(0)) u_lq (.clk, .rst_n, .vld(rq_v), .relu(1'b0), .sgn(1'b0), .acc({1'b0, PCOL ? pc_q[i] : hold[NQ * rq_j + i]}),
                                  .bias(20'sd0), .m(c_m0), .sh(c_sh), .omode(2'd2), .t(21'sd0), .r(19'sd0),
                                  .vld_o(qv[i]), .y_o(qy[i]), .b_o(b_unused));
    end
    logic [8:0] qidx [5];                                               // pq index of lane 0, aligned to the lane output
    assign qidx[0] = 9'(64 * hct + NQ * rq_j);
    for (genvar k = 0; k < 4; k++) begin : g_qd
        always_ff @(posedge clk) qidx[k + 1] <= qidx[k];
    end
    logic [6:0] pq [NK];
    logic [9:0] npq;
    logic       pq_wr;
    assign pq_wr = qv[0];
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin npq <= '0; pool_done <= 1'b0; end
        else begin
            pool_done <= 1'b0;
            if (pq_wr) begin
                for (int i = 0; i < NQ; i++) pq[qidx[4] + 9'(i)] <= qy[i][6:0];
                if (npq + 10'(NQ) == 10'(NK)) begin npq <= '0; pool_done <= 1'b1; end
                else npq <= npq + 10'(NQ);
            end
        end

    // ================================================================ FC macro
    localparam int NMAC = FW / 8, NM = NK / NMAC, MW = $clog2(NM), G = FW / 32;   // MACs / row, rows / class, classes / bias row
    logic          f_req;
    logic [AW-1:0] f_row;
    logic [FW-1:0] fr_r;
    if (FW == 256) begin : g_f256                                        // rf_sp 408 x 64, 4 lanes x 4 deep
        localparam int FD = 408;
        logic        f_ren_q;
        logic [8:0]  f_a_q;
        logic [1:0]  f_d_q, f_d_m;
        always_ff @(posedge clk) begin                                  // boundary: address registers
            f_ren_q <= f_req;
            f_a_q   <= 9'(f_row % 11'(FD));
            f_d_q   <= 2'(f_row / 11'(FD));
            f_d_m   <= f_d_q;
        end
        logic [63:0]  fqm [4][4];
        logic [255:0] fr_m;
        for (genvar l = 0; l < 4; l++) begin : g_fl
            for (genvar dd = 0; dd < 4; dd++) begin : g_fd
                wire hw = fc_we && h_addr / 11'(FD) == 11'(dd);
                qbt_rfsp #(64, FD) u_m (.clk, .ren(f_ren_q && f_d_q == 2'(dd)), .we(hw), .a(fc_we ? 9'(h_addr % 11'(FD)) : f_a_q),
                                        .wd(h_d[64 * l +: 64]), .q(fqm[l][dd]));
            end
            assign fr_m[64 * l +: 64] = fqm[l][f_d_m];
        end
        always_ff @(posedge clk) fr_r <= fr_m;                          // boundary: output register (row in x + 3)
    end else begin : g_f128                                             // one rf_sp NFR x 128 (sram_sp_adv 3232 x 128 m8)
        logic          f_ren_q;
        logic [AW-1:0] f_a_q;
        logic [FW-1:0] fr_m;
        always_ff @(posedge clk) begin                                  // boundary: address register
            f_ren_q <= f_req;
            f_a_q   <= f_row;
        end
        qbt_rfsp #(FW, NFR) u_m (.clk, .ren(f_ren_q), .we(fc_we), .a(fc_we ? h_addr : f_a_q), .wd(h_d), .q(fr_m));
        always_ff @(posedge clk) fr_r <= fr_m;                          // boundary: output register (row in x + 3)
    end

    // ================================================================ FC sequencer (one row per cycle)
    typedef struct packed { logic v; logic b; logic last; logic [6:0] j; logic [MW-1:0] m; } fm_t;
    logic       f_run;
    logic [AW-1:0] rr;
    logic [6:0] jj;
    logic [MW-1:0] mm;
    logic       isb;
    fm_t        fm [4];
    always_comb begin
        f_req = f_run;
        f_row = rr;
        fm[0] = '0;
        if (f_run) begin
            fm[0].v = 1'b1; fm[0].b = isb; fm[0].j = jj; fm[0].m = mm;
            fm[0].last = !isb && mm == MW'(NM - 1) && jj == c_ncls - 7'd1;
        end
    end
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin f_run <= 1'b0; rr <= '0; jj <= '0; mm <= '0; isb <= 1'b0; end
        else if (pool_done && !f_run) begin f_run <= 1'b1; rr <= '0; jj <= '0; mm <= '0; isb <= 1'b1; end
        else if (f_run) begin
            rr <= rr + AW'(1);
            if (isb) isb <= 1'b0;
            else begin
                mm <= mm + MW'(1);
                if (mm == MW'(NM - 1)) begin
                    jj <= jj + 7'd1;
                    if (jj == c_ncls - 7'd1) f_run <= 1'b0;
                    else if (jj % 7'(G) == 7'(G - 1)) isb <= 1'b1;
                end
            end
        end
    for (genvar k = 0; k < 3; k++) begin : g_fm
        always_ff @(posedge clk or negedge rst_n) if (!rst_n) fm[k + 1] <= '0; else fm[k + 1] <= fm[k];
    end
    // ================================================================ MAC: stage x + 3 (products, tree), x + 4 (accumulate)
    fm_t               m3, m4;
    logic [FW-1:0]     breg;
    logic signed [19:0] psum;
    assign m3 = fm[3];
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) m4 <= '0;
        else begin
            logic signed [19:0] s;
            logic [MW-1:0] mc;
`ifdef QBH_MUT_FCK
            mc = m3.m ^ MW'(1);                                            // mutant: pq chunk of the neighbouring row
`else
            mc = m3.m;
`endif
            s = '0;
            for (int n = 0; n < NMAC; n++) begin
                logic signed [19:0] wv, xv;
                wv = $signed({{12{fr_r[8 * n + 7]}}, fr_r[8 * n +: 8]});
                xv = $signed({13'd0, pq[NMAC * int'(mc) + n]});
                s = s + wv * xv;
            end
            m4 <= m3;
            if (m3.v && m3.b) breg <= fr_r;
            psum <= s;
        end
    logic signed [19:0] psa, psb;                                        // HP: partial sums (products 0..15, 16..31)
    if (HP) begin : g_hp
        localparam int NH = NMAC / 2;
        logic [6:0] xs [NMAC];
        always_ff @(posedge clk) begin
            logic [MW-1:0] mc2;
            logic signed [19:0] sa, sb;
`ifdef QBH_MUT_FCK
            mc2 = fm[2].m ^ MW'(1);
`else
            mc2 = fm[2].m;
`endif
            for (int n = 0; n < NMAC; n++) xs[n] <= pq[NMAC * int'(mc2) + n];
            sa = '0; sb = '0;
            for (int n = 0; n < NH; n++) begin
                sa = sa + $signed({{12{fr_r[8 * n + 7]}}, fr_r[8 * n +: 8]}) * $signed({13'd0, xs[n]});
                sb = sb + $signed({{12{fr_r[8 * (n + NH) + 7]}}, fr_r[8 * (n + NH) +: 8]}) * $signed({13'd0, xs[n + NH]});
            end
            psa <= sa; psb <= sb;
        end
    end else begin : g_nhp
        assign psa = '0;  assign psb = '0;
    end
    logic signed [31:0] acc;
    logic               f_done;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin lo_vld <= 1'b0; f_done <= 1'b0; end
        else begin
            logic signed [31:0] a;
            a = (m4.m == MW'(0) ? $signed(breg[32 * (m4.j % 7'(G)) +: 32]) : acc) + (HP ? 32'(psa) + 32'(psb) : 32'(psum));
            lo_vld <= m4.v && !m4.b && m4.m == MW'(NM - 1);
            f_done <= m4.v && m4.last;
            if (m4.v && !m4.b) acc <= a;
            lo_val <= a; lo_idx <= m4.j;
        end
    // FC active from its start to its last class out
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) fc_busy <= 1'b0;
        else if (pool_done) fc_busy <= 1'b1;
        else if (f_done) fc_busy <= 1'b0;
    assign busy = fc_busy || rq_v || pq_wr || npq != '0;
    // ================================================================ checks: pq / FC conflicts (overlap), overruns
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) err <= 1'b0;
        else err <= err | rq_ovr | (pq_wr && fc_busy) | (pool_done && fc_busy) | (c_nrows > AW'(NFR));
endmodule

// qb_hpcol (R7g, qb_head PCOL): pool slice of column C = channels 8 C .. 8 C + 7 (local index i): s4 / tacc / hold as in
//   qb_head (same enables, same reset behaviour: no register reset, updates only out of reset); po = the NQ hold words
//   hold[NQ (rq_j % (8 / NQ)) + i] when rq_j / (8 / NQ) == C (requant lane i reads channel NQ rq_j + i), else 0.
module qb_hpcol #(parameter int NQ = 4, parameter int C = 0) (
    input  logic             clk, rst_n, tap, k0, k3,
    input  logic [511:0]     fy,                                         // [16 (8 q + i) +: 16] = px q, channel 8 C + i
    input  logic [3:0]       rq_j,
    output logic [NQ*19-1:0] po
);
    localparam int NJ = 8 / NQ;                                         // conversion steps per column
    logic [18:0] s4 [8], tacc [8], hold [8];
    always_comb
        for (int i = 0; i < 8; i++) begin
            s4[i] = '0;
            for (int q = 0; q < 4; q++) begin
                logic signed [15:0] v;
                v = fy[16 * (8 * q + i) +: 16];
`ifdef QBH_MUT_RELU
                s4[i] = s4[i] + 19'(v);
`else
                s4[i] = s4[i] + ((v < 0) ? 19'd0 : 19'(v));
`endif
            end
        end
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin end
        else begin
            if (tap) for (int i = 0; i < 8; i++) tacc[i] <= (k0 ? 19'd0 : tacc[i]) + s4[i];
            if (tap && k3) for (int i = 0; i < 8; i++) hold[i] <= tacc[i] + s4[i];
        end
    wire [3:0] jl = 4'(int'(rq_j) % NJ);
    always_comb
        for (int i = 0; i < NQ; i++) begin
            logic [3:0] li;
`ifdef QBH_MUT_PCOL
            li = 4'(NQ * int'(jl ^ 4'd1) + i);                          // mutant: wrong half of the column's channels
`else
            li = 4'(NQ * int'(jl) + i);
`endif
            po[19 * i +: 19] = (int'(rq_j) / NJ == C) ? hold[li[2:0]] : 19'd0;
        end
endmodule
