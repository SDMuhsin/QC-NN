// qb_top: QC18B-ACC top level, R3a (ARCH.md v1.2 RTL plan R3, without the head): qb_core (CREG 1, WTP 1, FTP 1,
// PPOP 1, BRG 2) + qb_act2 (supply config C) + behavioural macros of the chosen geometries + descriptor sequencer +
// PPU write-back.  Image in the macros -> block 7's output stream in S (pool / FC = R3b).
//
// Time base: `now` = the compiler's model time (compile/supply.py config C with the write-back latency hook, exported
// by hw/tb/export_top.py); qb_act2 sees pass commands / tile tokens / load permissions on the model's cycles, so every
// item issues on the model's cycle (R2b contract).  D = 2 + AP + DIST: item issued at i -> core ctl / codes at i + D,
// act at i + D + 1 (qb_act2 act at i + 3 + AP, then DIST distribution registers).  Model capture time cap -> core ctl
// cycle cap + D; model drain start ds -> lane cycle e = ds + D + 4 (PPU port t = e - 1); outputs: b2 at cap + D + 4,
// fused f_y at e + 4 + k, wide w_y at e + 5 + k (FTP / WTP).  hw/tb/export_top.py lats() = these + write register.
//
// Macros (behavioural, registered boundaries: address / data registers in front, output register behind; qb_act2's
// m_ra / s_ra are already its registered outputs and rdq / sdq its output registers):
//   weights  rf_sp 204 x 144 x 48 (16 lanes x 3 deep), row = item codes (2304 b) of (pass, ct, chunk)
//   S        rf_2p 256 x 128 x 32 (1R + 1W per lane, bit-write mask), 16-b entries
//   B1, B2   rf_2p 128 x 128 x 4 each (512-b line), IMG rf_sp 128 x 128 x 4
//   params   one set (64 channel records) per (pass, ct) per word (deviation: see results/r3a.md)
// S layout:  stream (flat entry e = pixel * C + c, as the dataflow): address e >> 8, lane 8 (((e >> 6) & 3) ^ h(a)) +
//            ((e >> 3) & 7), entry e & 7, h(a) = (a ^ a >> 1) & 3 (XOR swizzle: the 4 pixels x 64 channels of a fused
//            drain cycle / hm job and the 32 values of a wide step hit distinct lanes for C = 64..512).
//            HQ (logical 128 + 8 pl + g, compile/layout_s.py) on lanes 0..15 at the same address, logical lane l at
//            physical (l + 2 pl + (g & 1)) & 15 (hm writes 16 lane-words / cycle on distinct lanes).
//            HQD (192 + 2 pl + h) on lanes 16..31 at 128 + 2 pl + h, Z (208 + 4 pl + q) on lanes 16..31 at 144 + 4 pl
//            + q, logical lane l at 16 + ((l + rD(pl)) & 15), rD = (pl & 3) + 8 (pl >> 2).
//            block-6 r (b6.sc -> b6.c2, 19 b as lo / hi entries): lanes 0..15, step k of channel tile ct at index
//            16 ct + (k >> 1) -> address 64 + idx (idx < 64) / 128 + idx, lane 8 (k & 1) + 2 q + (col >> 2), entries
//            2 (col & 3) + {lo, hi}.  No read-port conflicts by construction (asserted: err).
// Map layout: compile/layout.py lines; physical macro (m + f(line)) & 3, f = (line ^ line >> 1) & 1 for B1 / B2 (the
//            two chunk words of a fused drain cycle hit distinct macros), IMG unswizzled.
// R3b hook (parameter R3B, default 0 = R3a as above): R3B = 1 replaces the per-image time-triggered queues by the
// image-independent sequencer qb_seq (hw/rtl/qb_seq.sv: static issue order + stamp scoreboard + runtime gating; pass
// starts on done, tile tokens, load permissions, capture / PPU job events) and the one-set-per-word params model by
// qb_prm (9 x rf_sp 240 x 144 bank, staged per consumer; per-pass common pf / pw bits in the pass table [93:89]).
// R3c hook (parameter HSEL, default 0 = as above): HSEL = 1 switches a macro's address mux to the host address only
// on a host write of that macro (h_we && h_sel == its select) instead of on any h_we, so the host can load the next
// image into IMG while the image runs (qb_chip, hw/rtl/qb_chip.sv) without disturbing the weight / params reads.
// R4 hook (define QB_TECH, default off): synthesis / tech build of qb_chip (R3B = 1).  The R3a-only memories (pass
// queues pq / tq / cq / fq / wq, load table lt, one-set-per-word params prm: ~0.7 Mb of flops, dead when R3B = 1) are
// neither written nor read (reads tied to 0), the bench read-back dbg_sq (hierarchical into the S model) is 0, and the
// behavioural qbt_rfsp / qbt_rf2p below are replaced by hw/tech/qb_mem_tech.sv (same ports, ARM macros).  R4 also
// renamed the functional taps used by qb_chip / qb_head: dbg_{fv,fpi,fct,fk,fy} -> wb_* (fused write-back bus),
// dbg_{aeot,actx,apic0,apic1} -> ae_{eot,ctx,pic0,pic1} (act-supply tile ends).
// R4b hooks (defines, defaults = R4): QB_SEQ_RT = 1 builds the retimed sequencer hw/rtl/qb_seq_rt.sv (same cycles;
// in simulation the R3b qb_seq runs in lockstep and any output difference sets err; QBT_NOLOCK disables it),
// QB_SEQ_LSW = stored load-permission age width (qb_seq_rt), QB_PRM_NFF / NFW / NFT = qb_prm fetch-list depths,
// QB_TOP_SROT = 1: the act-port S read rotation (s_q) as a group mux + log rotator (same function, less area),
// QB_TOP_WBR = 1: the S write requests (stream / HQ / HQD / Z / r / b6.c2) as lane-group selects + log rotators.
`ifndef QB_SEQ_NT
`define QB_SEQ_NT 1024
`endif
`ifndef QB_SEQ_NLT
`define QB_SEQ_NLT 1024
`endif
`ifndef QB_SEQ_DSCM
`define QB_SEQ_DSCM 0
`endif
`ifndef QB_SEQ_RT
`define QB_SEQ_RT 0
`endif
`ifndef QB_SEQ_LSW
`define QB_SEQ_LSW 16
`endif
`ifndef QB_TOP_SROT
`define QB_TOP_SROT 0
`endif
`ifndef QB_TOP_WBR
`define QB_TOP_WBR 0
`endif
`ifndef QB_PRM_NFF
`define QB_PRM_NFF 256
`endif
`ifndef QB_PRM_NFW
`define QB_PRM_NFW 256
`endif
`ifndef QB_PRM_NFT
`define QB_PRM_NFT 256
`endif
module qb_top #(parameter int DIST = 1, parameter int AP = 1, parameter bit R3B = 0, parameter bit HSEL = 0) (
    input  logic          clk, rst_n,
    input  logic          go,                      // start of an image (descriptors / macros loaded)
    // host load port (descriptor memories, weights, params, image)
    input  logic          h_we,
    input  logic [3:0]    h_sel,                   // 0 weights 1 params 2 image 3 PT 4 P0 5 P1 6 TQ 7 CQ 8 FQ 9 WQ 10 LT 15 counts
    input  logic [9:0]    h_addr,
    input  logic [5188:0] h_data,
    output logic [15:0]   now,
    output logic          err,
    // fused write-back bus wb_* and act tile ends ae_* (functional: qb_chip / qb_head); dbg_*: bench taps only
    output logic          wb_fv, dbg_wv, dbg_bv,
    output logic [4:0]    wb_fpi, dbg_wpi, dbg_bpi,
    output logic [6:0]    dbg_ftp,
    output logic [3:0]    wb_fct,
    output logic [1:0]    wb_fk,
    output logic [4351:0] wb_fy,
    output logic [255:0]  dbg_fb,
    output logic [607:0]  dbg_wy,
    output logic [31:0]   dbg_wb,
    output logic [1023:0] dbg_b2,
    output logic          dbg_av, ae_ctx, ae_eot, dbg_af, dbg_aneg, dbg_astem, dbg_ag3n,
    output logic [2:0]    dbg_apl, dbg_act_ct,
    output logic [3:0]    dbg_ach,
    output logic [5:0]    dbg_atile,
    output logic [4607:0] dbg_act,
    output logic [4:0]    ae_pic0, ae_pic1,
    input  logic [7:0]    dbg_sa,                  // bench read-back of S (all lanes of one address)
    output logic [4095:0] dbg_sq
);
    localparam int D = 2 + AP + DIST;
    localparam int NLF = 256, NLW = 32;
    initial if (D < 4) $fatal(1, "qb_top: AP + DIST must be >= 2");

    // ================================================================ descriptor memories (host-loaded)
    logic [95:0] pt [32];
    logic [20:0] pq [2][32];
    logic [16:0] tq [1024];
    logic [32:0] cq [1024];
    logic [31:0] fq [1024];
    logic [31:0] wq [64];
    logic [41:0] lt [1024];
    logic [10:0] n_pq [2], n_tq, n_cq, n_fq, n_wq;
    logic [5188:0] prm [128];
`ifndef QB_TECH
    always_ff @(posedge clk)
        if (h_we) unique case (h_sel)
            4'd1:  prm[h_addr[6:0]] <= h_data;
            4'd3:  pt[h_addr[4:0]] <= h_data[95:0];
            4'd4:  pq[0][h_addr[4:0]] <= h_data[20:0];
            4'd5:  pq[1][h_addr[4:0]] <= h_data[20:0];
            4'd6:  tq[h_addr] <= h_data[16:0];
            4'd7:  cq[h_addr] <= h_data[32:0];
            4'd8:  fq[h_addr] <= h_data[31:0];
            4'd9:  wq[h_addr[5:0]] <= h_data[31:0];
            4'd10: lt[h_addr] <= h_data[41:0];
            4'd15: unique case (h_addr[2:0])
                       3'd0: n_pq[0] <= h_data[10:0];
                       3'd1: n_pq[1] <= h_data[10:0];
                       3'd2: n_tq <= h_data[10:0];
                       3'd3: n_cq <= h_data[10:0];
                       3'd4: n_fq <= h_data[10:0];
                       3'd5: n_wq <= h_data[10:0];
                       default: ;
                   endcase
            default: ;
        endcase
`else
    always_ff @(posedge clk) if (h_we && h_sel == 4'd3) pt[h_addr[4:0]] <= h_data[95:0];
`endif
    // pass-table fields
    function automatic logic [3:0] pt_cfg  (input logic [88:0] w); return w[3:0];   endfunction
    function automatic logic [4:0] pt_nch  (input logic [88:0] w); return w[8:4];   endfunction
    function automatic logic [3:0] pt_nct  (input logic [88:0] w); return w[12:9];  endfunction
    function automatic logic [6:0] pt_ntl  (input logic [88:0] w); return w[19:13]; endfunction
    function automatic logic       pt_i8   (input logic [88:0] w); return w[20];    endfunction
    function automatic logic       pt_stem (input logic [88:0] w); return w[21];    endfunction
    function automatic logic [8:0] pt_sb   (input logic [88:0] w); return w[30:22]; endfunction
    function automatic logic [3:0] pt_kind (input logic [88:0] w); return w[34:31]; endfunction  // stem bc1 bsc bc2 hm wc1 wsc wc2
    function automatic logic [1:0] pt_src  (input logic [88:0] w); return w[36:35]; endfunction  // B1 B2 IMG S
    function automatic logic [9:0] pt_wb   (input logic [88:0] w); return w[46:37]; endfunction
    function automatic logic [4:0] pt_wr   (input logic [88:0] w); return w[51:47]; endfunction
    function automatic logic [2:0] pt_lgc  (input logic [88:0] w); return w[54:52]; endfunction  // log2(C / 64)
    function automatic logic [2:0] pt_lgw  (input logic [88:0] w); return w[57:55]; endfunction  // log2(W out)
    function automatic logic [9:0] pt_pb   (input logic [88:0] w); return w[67:58]; endfunction
    function automatic logic       pt_b1   (input logic [88:0] w); return w[68];    endfunction
    function automatic logic [9:0] pt_lb   (input logic [88:0] w); return w[78:69]; endfunction
    function automatic logic [9:0] pt_lc   (input logic [88:0] w); return w[88:79]; endfunction
    function automatic logic [1:0] h2 (input logic [7:0] a); return a[1:0] ^ a[2:1]; endfunction
    function automatic logic [3:0] rotd (input logic [2:0] pl); return {pl[2], 1'b0, pl[1:0]}; endfunction
    function automatic logic       fsw (input logic [6:0] line); return line[0] ^ line[1]; endfunction

    // ================================================================ time base, queues
    logic run;
    logic [2:0] clr;                                     // flag-store clear sequence at go
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin run <= 1'b0; now <= '0; end
        else if (go) begin run <= 1'b1; now <= '0; end
        else if (run) now <= now + 16'd1;
    logic [10:0] p_ptr [2], t_ptr, c_ptr, f_ptr, w_ptr;
`ifndef QB_TECH
    wire [20:0] ph0 = pq[0][p_ptr[0][4:0]], ph1 = pq[1][p_ptr[1][4:0]];
    wire [16:0] th = tq[t_ptr[9:0]];
    wire [32:0] chd_a = cq[c_ptr[9:0]];
`else
    wire [20:0] ph0 = '0, ph1 = '0;
    wire [16:0] th = '0;
    wire [32:0] chd_a = '0;
`endif
`ifndef QB_TECH
    wire [31:0] fh_a = fq[f_ptr[9:0]], wh_a = wq[w_ptr[5:0]];
`else
    wire [31:0] fh_a = '0, wh_a = '0;
`endif
    wire [1:0] p_fire_a = {run && p_ptr[1] < n_pq[1] && ph1[20:5] == now, run && p_ptr[0] < n_pq[0] && ph0[20:5] == now};
    wire t_fire = run && t_ptr < n_tq && th[16:1] == now;
    wire c_fire_a = run && c_ptr < n_cq && chd_a[32:17] == now;
    wire f_fire_a = run && f_ptr < n_fq && fh_a[31:16] == now;
    wire w_fire_a = run && w_ptr < n_wq && wh_a[31:16] == now;
    // R3B: the same events from qb_seq (g_r3b below)
    logic [1:0]  s_pfire, s_tgo, s_lok;
    logic [4:0]  s_ppi [2];
    logic [15:0] s_lseq0, s_lseq1, s_fjob, s_wjob;
    logic        s_cfire, s_ccmp, s_ffire, s_wfire;
    logic [4:0]  s_cpi;  logic [6:0] s_ctp;  logic [3:0] s_cct;
    wire [1:0]  p_fire = R3B ? s_pfire : p_fire_a;
    wire        c_fire = R3B ? s_cfire : c_fire_a;
    wire        f_fire = R3B ? s_ffire : f_fire_a;
    wire        w_fire = R3B ? s_wfire : w_fire_a;
    wire [32:0] chd = R3B ? {16'd0, s_cct, s_ctp, s_cpi, s_ccmp} : chd_a;
    wire [31:0] fh = R3B ? {16'd0, s_fjob} : fh_a, wh = R3B ? {16'd0, s_wjob} : wh_a;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin p_ptr[0] <= '0; p_ptr[1] <= '0; t_ptr <= '0; c_ptr <= '0; f_ptr <= '0; w_ptr <= '0; end
        else if (go) begin p_ptr[0] <= '0; p_ptr[1] <= '0; t_ptr <= '0; c_ptr <= '0; f_ptr <= '0; w_ptr <= '0; end
        else begin
            if (p_fire[0]) p_ptr[0] <= p_ptr[0] + 11'd1;
            if (p_fire[1]) p_ptr[1] <= p_ptr[1] + 11'd1;
            if (t_fire) t_ptr <= t_ptr + 11'd1;
            if (c_fire) c_ptr <= c_ptr + 11'd1;
            if (f_fire) f_ptr <= f_ptr + 11'd1;
            if (w_fire) w_ptr <= w_ptr + 11'd1;
        end

    // ================================================================ qb_act2 + its R3 interface
    logic [1:0]       start, busy, done, tgo, l_ok;
    logic [1:0][3:0]  c_cfg, c_nct;
    logic [1:0][4:0]  c_nchunk;
    logic [1:0][6:0]  c_ntile;
    logic [1:0]       c_int8, c_stem;
    logic [1:0][8:0]  c_base;
    logic [15:0]      l_seq0, l_seq1;
    logic [9:0]       l_pos0, l_pos1;
    logic             f_clr, f_we, f_nz;
    logic [1:0]       f_bank;
    logic [6:0]       f_idx;
    logic             m_ren, m_ctx, s_ren, s_ctx, a_err;
    logic [8:0]       m_ra;
    logic [7:0]       s_ra;
    logic [511:0]     m_q;
    logic [2047:0]    s_q;
    logic             d_vld, d_first, d_eot, d_neg, d_stem, d_g3n, d_ctx;
    logic [2:0]       d_plane, d_ct;
    logic [3:0]       d_chunk;
    logic [5:0]       d_tile;
    logic [4607:0]    a_act;
    logic             a_vld, a_first, a_eot, a_neg, a_stem, a_g3n, a_ctx;
    logic [2:0]       a_plane, a_ct;
    logic [3:0]       a_chunk;
    logic [5:0]       a_tile;

    logic [4:0] cpi [2];                                 // pass of each context
    logic [1:0] cval;
    logic [9:0] lptr [2], lend [2];
    logic [2:0] fl_quiet;                                // per flag bank: queue empty for >= 2 cycles
    for (genvar c = 0; c < 2; c++) begin : g_cx
        wire [20:0] ph_a = c ? ph1 : ph0;
        wire [4:0]  ph = R3B ? s_ppi[c] : ph_a[4:0];
        wire [88:0] pw_ = pt[ph[4:0]];
        assign start[c]    = p_fire[c];
        assign c_cfg[c]    = pt_cfg(pw_);
        assign c_nchunk[c] = pt_nch(pw_);
        assign c_nct[c]    = pt_nct(pw_);
        assign c_ntile[c]  = pt_ntl(pw_);
        assign c_int8[c]   = pt_i8(pw_);
        assign c_stem[c]   = pt_stem(pw_);
        assign c_base[c]   = pt_sb(pw_);
        assign tgo[c]      = R3B ? s_tgo[c] : t_fire && th[0] == c[0];
        // load permission: first table entry whose position is beyond the loader's (one step per cycle)
        wire [9:0]  pos = c ? l_pos1 : l_pos0;
`ifndef QB_TECH
        wire [41:0] e0 = lt[lptr[c]];
`else
        wire [41:0] e0 = '0;
`endif
        wire [9:0]  cur = (lptr[c] < lend[c] && e0[9:0] <= pos) ? lptr[c] + 10'd1 : lptr[c];
`ifndef QB_TECH
        wire [41:0] e1 = lt[cur];
`else
        wire [41:0] e1 = '0;
`endif
        wire        i8 = pt_i8(pt[cpi[c]]);
        wire [3:0]  cf = pt_cfg(pt[cpi[c]]);
        assign l_ok[c] = R3B ? s_lok[c] : cval[c] && !start[c] && cur < lend[c] && e1[9:0] > pos && now >= e1[25:10] &&
                         (!i8 || fl_quiet[cf == 4'd8 ? 0 : cf == 4'd9 ? 1 : 2]);
        if (c == 0) assign l_seq0 = R3B ? s_lseq0 : e1[41:26]; else assign l_seq1 = R3B ? s_lseq1 : e1[41:26];
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) begin cval[c] <= 1'b0; cpi[c] <= '0; lptr[c] <= '0; lend[c] <= '0; end
            else if (start[c]) begin
                cval[c] <= 1'b1; cpi[c] <= ph[4:0]; lptr[c] <= pt_lb(pw_); lend[c] <= pt_lb(pw_) + pt_lc(pw_);
            end else lptr[c] <= cur;
    end

    qb_act2 #(.ACT_PIPE(AP)) u_act (
        .clk, .rst_n, .start, .c_cfg, .c_nchunk, .c_nct, .c_ntile, .c_int8, .c_stem, .c_base, .busy, .done, .tgo, .l_ok,
        .l_seq0, .l_seq1, .l_pos0, .l_pos1, .f_clr, .f_we, .f_nz, .f_bank, .f_idx, .m_ren, .m_ra, .m_ctx, .m_q, .s_ren,
        .s_ra, .s_ctx, .s_q, .d_vld, .d_first, .d_eot, .d_neg, .d_stem, .d_g3n, .d_ctx, .d_plane, .d_chunk, .d_ct,
        .d_tile, .act(a_act), .a_vld, .a_first, .a_eot, .a_neg, .a_stem, .a_g3n, .a_ctx, .a_plane, .a_chunk, .a_ct,
        .a_tile, .err(a_err));

    // ================================================================ act distribution (DIST registered stages)
    logic [4607:0] actd [DIST + 1];
    assign actd[0] = a_act;
    for (genvar k = 0; k < DIST; k++) begin : g_dist
        qbt_dreg #(4608) u_d (.clk, .d(actd[k]), .q(actd[k + 1]));
    end

    // ================================================================ weights: rf_sp 204 x 144, 16 lanes x 3 deep
    logic        w_req;
    logic [9:0]  w_row;
    always_comb begin
        logic [88:0] p;
        p = pt[cpi[d_ctx]];
        w_req = d_vld;
        w_row = pt_wb(p) + 10'(d_ct) * 10'(pt_wr(p)) + (pt_stem(p) ? 10'd0 : 10'(d_chunk));
    end
    logic        w_ren_q;
    logic [7:0]  w_a_q;
    logic [1:0]  w_d_q, w_d_m;
    always_ff @(posedge clk) begin                       // boundary: address registers
        w_ren_q <= w_req;
        w_a_q   <= 8'(w_row % 10'd204);
        w_d_q   <= 2'(w_row / 10'd204);
        w_d_m   <= w_d_q;
    end
    wire hw_w = HSEL ? (h_we && h_sel == 4'd0) : h_we;      // host owns the weight-macro address
    wire hw_i = HSEL ? (h_we && h_sel == 4'd2) : h_we;      // host owns the IMG address
    logic [143:0] wqm [16][3];
    logic [2303:0] cd_m, cd_r;
    for (genvar l = 0; l < 16; l++) begin : g_wl
        for (genvar dd = 0; dd < 3; dd++) begin : g_wd
            qbt_rfsp #(144, 204) u_m (.clk, .ren(w_ren_q && w_d_q == dd), .we(h_we && h_sel == 4'd0 && h_addr / 10'd204 == dd),
                                      .a(hw_w ? 8'(h_addr % 10'd204) : w_a_q), .wd(h_data[144*l +: 144]), .q(wqm[l][dd]));
        end
        assign cd_m[144*l +: 144] = wqm[l][w_d_m];
    end
    always_ff @(posedge clk) cd_r <= cd_m;                // boundary: output register (codes at issue + 4)
    // align codes / item controls to the ctl cycle (issue + D)
    logic [2303:0] cdp [D - 3];
    assign cdp[0] = cd_r;
    for (genvar k = 0; k < D - 4; k++) begin : g_cdp
        qbt_dreg #(2304) u_d (.clk, .d(cdp[k]), .q(cdp[k + 1]));
    end
    logic [7:0] ictl [D + 1];                            // {g3n, stem, neg, plane[2:0], first, valid}, issue + k
    assign ictl[0] = '0;
    assign ictl[1] = {d_g3n, d_stem, d_neg, d_plane, d_first, d_vld};
    for (genvar k = 1; k < D; k++) begin : g_ictl
        always_ff @(posedge clk or negedge rst_n) if (!rst_n) ictl[k + 1] <= '0; else ictl[k + 1] <= ictl[k];
    end

    // ================================================================ capture events (cap at model cap -> ctl cap + D)
    typedef struct packed { logic v; logic cmp; logic [4:0] pi; logic [6:0] tp; logic [3:0] ct; } cev_t;
    cev_t cdl [D + 5];
    assign cdl[0] = c_fire ? '{v: 1'b1, cmp: chd[0], pi: chd[5:1], tp: chd[12:6], ct: chd[16:13]} : '0;
    for (genvar k = 0; k < D + 4; k++) begin : g_cdl
        always_ff @(posedge clk or negedge rst_n) if (!rst_n) cdl[k + 1] <= '0; else cdl[k + 1] <= cdl[k];
    end
    cev_t cct;
`ifdef QBT_MUT_CAP
    assign cct = cdl[D - 1];                             // mutant: capture one cycle early
`else
    assign cct = cdl[D];                                 // ctl cycle
`endif
    logic [9:0] ctl;
    assign ctl = {cct.v && cct.cmp, cct.v && !cct.cmp, ictl[D]};
    logic [1087:0] t2_q;
    always_ff @(posedge clk) begin                       // T2 at ctl + 2
        cev_t c1_;
        c1_ = cdl[D + 1];
`ifndef QB_TECH
        t2_q <= prm[pt_pb(pt[c1_.pi]) + 10'(c1_.ct)][1087:0];
`else
        t2_q <= '0;
`endif
    end

    // ================================================================ PPU step streams
    // fused unit: a job (drain of stem / sc / c2 tile, or hm tile) fires at ds; step k (0..3) at ds + 1 + k
    typedef struct packed { logic v; logic hm; logic [2:0] kind; logic [4:0] pi; logic [6:0] tp; logic [3:0] ct; logic [4:0] k; } stp_t;
    stp_t fst, wst;
    logic [1:0] fk;  logic fbusy;  logic [4:0] wk;  logic wbusy;
    stp_t fjob, wjob;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin fbusy <= 1'b0; fk <= '0; wbusy <= 1'b0; wk <= '0; fjob <= '0; wjob <= '0; end
        else begin
            if (f_fire) begin
                logic [3:0] kd;
                kd = pt_kind(pt[fh[4:0]]);
                fjob <= '{v: 1'b1, hm: kd == 4'd4, kind: kd[2:0], pi: fh[4:0], tp: fh[11:5], ct: fh[15:12], k: '0};
                fbusy <= 1'b1; fk <= '0;
            end else if (fbusy) begin
                fk <= fk + 2'd1;
                if (fk == 2'd3) fbusy <= 1'b0;
            end
            if (w_fire) begin
                logic [3:0] kd;
                kd = pt_kind(pt[wh[4:0]]);
                wjob <= '{v: 1'b1, hm: 1'b0, kind: kd[2:0], pi: wh[4:0], tp: wh[11:5], ct: wh[15:12], k: '0};
                wbusy <= 1'b1; wk <= '0;
            end else if (wbusy) begin
                wk <= wk + 5'd1;
                if (wk == 5'd31) wbusy <= 1'b0;
            end
        end
    always_comb begin
        fst = fjob; fst.v = fbusy; fst.k = {3'd0, fk};
        wst = wjob; wst.v = wbusy; wst.k = wk;
    end
    wire f_ovl = f_fire && fbusy && fk != 2'd3;           // model guarantees >= 4 cycles between fused jobs
    wire w_ovl = w_fire && wbusy && wk != 5'd31;
    stp_t fdl [D + 9], wdl [D + 10];
    assign fdl[0] = fst;
    assign wdl[0] = wst;
    for (genvar k = 0; k < D + 8; k++) begin : g_fdl
        always_ff @(posedge clk or negedge rst_n) if (!rst_n) fdl[k + 1] <= '0; else fdl[k + 1] <= fdl[k];
    end
    for (genvar k = 0; k < D + 9; k++) begin : g_wdl
        always_ff @(posedge clk or negedge rst_n) if (!rst_n) wdl[k + 1] <= '0; else wdl[k + 1] <= wdl[k];
    end
    // PPU ports at step + D + 2
    stp_t fp, wp;
    assign fp = fdl[D + 2];
    assign wp = wdl[D + 2];
    logic f_vld, f_src, f_sh, p_ld, w_vld, w_sh, w_ld;
    assign f_vld = fp.v;
    assign f_src = fp.v && fp.hm;
    assign f_sh  = fp.v && !fp.hm && fp.k != 5'd3;
    assign p_ld  = fp.v && (fp.hm || fp.k == 5'd0);
    assign w_vld = wp.v;
    assign w_sh  = wp.v && wp.k != 5'd31;
    assign w_ld  = wp.v && wp.k == 5'd0;
    logic [5188:0] pf_q;
    logic [5058:0] pw_q;
    always_ff @(posedge clk) begin                        // parameter sets registered at step + D + 1
        stp_t a, b;
        a = fdl[D + 1]; b = wdl[D + 1];
`ifndef QB_TECH
        pf_q <= prm[pt_pb(pt[a.pi]) + (a.hm ? 10'd0 : 10'(a.ct))];
        pw_q <= prm[pt_pb(pt[b.pi]) + 10'(b.ct)][5058:0];
`else
        pf_q <= '0;
        pw_q <= '0;
`endif
    end

    // ================================================================ S: rf_2p 256 x 128 x 32
    logic [31:0]       s_mren, s_we;
    logic [7:0]        s_mra [32], s_wa [32];
    logic [127:0]      s_wd [32], s_wm [32], s_mq [32];
    logic [31:0]       s_rwc;                              // read + write of one address in one cycle (rf_2p: X)
    logic [7:0]        b_rwc;
    for (genvar l = 0; l < 32; l++) begin : g_s
        qbt_rf2p #(128, 256) u_m (.clk, .ren(s_mren[l]), .ra(s_mra[l]), .we(s_we[l]), .wa(s_wa[l]), .wd(s_wd[l]),
                                  .wm(s_wm[l]), .q(s_mq[l]), .conf(s_rwc[l]));
`ifndef QB_TECH
        assign dbg_sq[128 * l +: 128] = u_m.mem[dbg_sa];
`else
        assign dbg_sq[128 * l +: 128] = '0;
`endif
    end
    // ---- reader requests (registered boundary) for drains / hm / wide r, macro at request + 1, data at + 3
    logic [31:0]  rd_en, rd_en_q;
    logic [7:0]   rd_a [32], rd_a_q [32];
    // fused reads: bc2 s_in / r at step + D + 1 (s_rd at e + k + 1), hm x at step + D (s_rd at e + k)
    stp_t frd_d, frd_h, wrd;
    assign frd_d = fdl[D + 1];
    assign frd_h = fdl[D];
    assign wrd = wdl[D + 1];
    wire f_rconf = frd_d.v && !frd_d.hm && frd_d.kind == 3'd3 && frd_h.v && frd_h.hm;   // hm job right after a c2 drain
    logic [1:0] f_pg [4];                                  // physical lane group of pixel q (for the s_rd routing)
    logic       f_rv;                                      // a fused read is in flight this cycle
    always_comb begin
        stp_t s;  logic [88:0] p;  logic [15:0] px;  logic [23:0] e;  logic [7:0] a;  logic [1:0] pg;  logic [6:0] idx;
        rd_en = '0;
        for (int l = 0; l < 32; l++) rd_a[l] = '0;
        for (int q = 0; q < 4; q++) f_pg[q] = '0;
        f_rv = 1'b0;
        s = (frd_h.v && frd_h.hm) ? frd_h : frd_d;
        p = pt[s.pi];
        px = '0; e = '0; a = '0; pg = '0; idx = '0;
        if ((frd_d.v && !frd_d.hm && frd_d.kind == 3'd3) || (frd_h.v && frd_h.hm)) begin
            f_rv = 1'b1;
            for (int q = 0; q < 4; q++) begin
                px = 16'(s.tp) * 16 + 16'(s.k) * 4 + 16'(q);
                e  = (24'(px) << (6 + (s.hm ? 2 : pt_lgc(p)))) + 24'(s.ct) * 64;
                a  = e[15:8];
                pg = e[7:6] ^ h2(a);
                f_pg[q] = pg;
                for (int col = 0; col < 8; col++) begin rd_en[8 * pg + col] = 1'b1; rd_a[8 * pg + col] = a; end
            end
        end
        if (wrd.v && wrd.kind == 3'd7) begin              // b6.c2: r lo / hi of step k
            idx = 7'(wrd.ct) * 16 + 7'(wrd.k[4:1]);
            a   = idx < 7'd64 ? 8'd64 + 8'(idx) : 8'd128 + 8'(idx);
            for (int j = 0; j < 8; j++) begin rd_en[8 * wrd.k[0] + j] = 1'b1; rd_a[8 * wrd.k[0] + j] = a; end
        end
    end
    wire rd_conf = f_rv && wrd.v && wrd.kind == 3'd7;     // fused and wide readers in one cycle (never by schedule)
    always_ff @(posedge clk) begin rd_en_q <= rd_en; for (int l = 0; l < 32; l++) rd_a_q[l] <= rd_a[l]; end
    // ---- qb_act2 S port (s_ra logical -> group / address / rotation)
    logic        s_grp;  logic [7:0] s_pa;  logic [3:0] s_rot;
    always_comb begin
        logic [7:0] o;
        if (s_ra < 8'd192) begin
            o = s_ra - 8'd128; s_grp = 1'b0; s_pa = s_ra; s_rot = {o[5:3], 1'b0} + {3'd0, o[0]};
        end else if (s_ra < 8'd208) begin
            o = s_ra - 8'd192; s_grp = 1'b1; s_pa = 8'd128 + o; s_rot = rotd(o[3:1]);
        end else begin
            o = s_ra - 8'd208; s_grp = 1'b1; s_pa = 8'd144 + o; s_rot = rotd(o[4:2]);
        end
    end
    logic s_conf;
    always_comb begin
        s_conf = 1'b0;
        for (int l = 0; l < 32; l++) begin
            logic ia;
            ia = s_ren && (l / 16 == s_grp);
            s_mren[l] = ia || rd_en_q[l];
            s_mra[l]  = ia ? s_pa : rd_a_q[l];
            if (ia && rd_en_q[l]) s_conf = 1'b1;
        end
    end
    logic s_grp_q;  logic [3:0] s_rot_q;
    always_ff @(posedge clk) begin s_grp_q <= s_grp; s_rot_q <= s_rot; end
    if (`QB_TOP_SROT) begin : g_srot                       // R4b: group mux + 4-stage log rotator (same function)
        always_comb begin
            logic [2047:0] x;
            for (int l = 0; l < 16; l++) x[128 * l +: 128] = s_grp_q ? s_mq[16 + l] : s_mq[l];
            if (s_rot_q[0]) x = {x[127:0], x[2047:128]};
            if (s_rot_q[1]) x = {x[255:0], x[2047:256]};
            if (s_rot_q[2]) x = {x[511:0], x[2047:512]};
            if (s_rot_q[3]) x = {x[1023:0], x[2047:1024]};
            s_q = x;
        end
    end else begin : g_nsrot
        always_comb for (int l = 0; l < 16; l++) s_q[128 * l +: 128] = s_mq[16 * s_grp_q + ((l + s_rot_q) & 15)];
    end
    // ---- reader output registers -> s_rd (fused) / w_r (wide)
    logic [4095:0] rq_r;
    logic [1:0]    f_pg1 [4], f_pg2 [4], f_pg3 [4];
    logic          k0_1, k0_2, k0_3;
    logic [2:0]    fv_p, wv_p;                                // reader valid, delayed to the data cycle
    always_ff @(posedge clk) begin
        fv_p <= {fv_p[1:0], f_rv};
        wv_p <= {wv_p[1:0], wrd.v && wrd.kind == 3'd7};
        for (int l = 0; l < 32; l++) rq_r[128 * l +: 128] <= s_mq[l];
        f_pg1 <= f_pg; f_pg2 <= f_pg1; f_pg3 <= f_pg2;
        k0_1 <= wrd.k[0]; k0_2 <= k0_1; k0_3 <= k0_2;
    end
    logic [NLF*17-1:0] s_rd;
    logic [NLW*19-1:0] w_r;
    always_comb begin
        for (int q = 0; q < 4; q++)
            for (int col = 0; col < 8; col++)
                for (int i = 0; i < 8; i++)
                    s_rd[17 * (64 * q + 8 * col + i) +: 17] = fv_p[2] ? 17'($signed(rq_r[128 * (8 * f_pg3[q] + col) + 16 * i +: 16]))
                                                                      : 17'd0;
        for (int q = 0; q < 4; q++)
            for (int col = 0; col < 8; col++) begin
                logic [127:0] lw;
                lw = rq_r[128 * (8 * k0_3 + 2 * q + col / 4) +: 128];
                w_r[19 * (8 * q + col) +: 19] = wv_p[2] ? {lw[32 * (col % 4) + 16 +: 3], lw[32 * (col % 4) +: 16]} : 19'd0;
            end
    end

    // ================================================================ maps: B1 / B2 rf_2p 128 x 128 x 4, IMG rf_sp 128 x 128 x 4
    logic [3:0]   b_we [2];
    logic [6:0]   b_wa [2][4];
    logic [127:0] b_wd [2][4], b_wm [2][4], b_q [2][4], i_q [4];
    logic [1:0]   m_src, m_src_q;
    logic         m_f_q;
    assign m_src = pt_src(pt[cpi[m_ctx]]);
    for (genvar mp = 0; mp < 2; mp++) begin : g_map
        for (genvar m = 0; m < 4; m++) begin : g_mm
            qbt_rf2p #(128, 128) u_m (.clk, .ren(m_ren && m_src == mp), .ra(m_ra[6:0]), .we(b_we[mp][m]), .wa(b_wa[mp][m]),
                                      .wd(b_wd[mp][m]), .wm(b_wm[mp][m]), .q(b_q[mp][m]), .conf(b_rwc[4 * mp + m]));
        end
    end
    for (genvar m = 0; m < 4; m++) begin : g_img
        qbt_rfsp #(128, 128) u_m (.clk, .ren(m_ren && m_src == 2'd2), .we(h_we && h_sel == 4'd2),
                                  .a(hw_i ? h_addr[6:0] : m_ra[6:0]), .wd(h_data[128*m +: 128]), .q(i_q[m]));
    end
    always_ff @(posedge clk) begin m_src_q <= m_src; m_f_q <= fsw(m_ra[6:0]); end
    always_comb
        for (int m = 0; m < 4; m++)
            m_q[128 * m +: 128] = m_src_q == 2'd2 ? i_q[m] : b_q[m_src_q[0]][(m + m_f_q) & 3];

    // ================================================================ core
    logic [16*36*8-1:0]   act_c;                      // R4: was 16*8*36*8 (zero-extended into the 4608-b port; DC LINK-3)
    logic [1023:0]        b2;
    logic                 b2_vld, f_vld_o, w_vld_o;
    logic [NLF*17-1:0]    f_y;
    logic [NLF-1:0]       f_b;
    logic [NLW*19-1:0]    w_y;
    logic [NLW-1:0]       w_b;
    assign act_c = actd[DIST];
    logic [1087:0] t2_c;  logic [5188:0] pf_c;  logic [5058:0] pw_c;
    qb_core #(.CREG(1), .WTP(1), .FTP(1), .PPOP(1), .BRG(2)) u_core (
        .clk, .rst_n, .cd(cdp[D - 4]), .ctl, .act(act_c), .t2(t2_c), .b2, .b2_vld, .f_vld, .f_src, .f_sh, .p_ld,
        .pf(pf_c), .s_rd, .f_vld_o, .f_y, .f_b, .w_vld, .w_sh, .w_ld, .pw(pw_c), .w_r, .w_vld_o, .w_y, .w_b);

    // ================================================================ write-back
    stp_t fo, wo;
    cev_t bo;
    assign fo = fdl[D + 7];
    assign wo = wdl[D + 8];
    assign bo = cdl[D + 4];
    // S write requests (comb) -> boundary registers
    logic [31:0]  sw_en;
    logic [7:0]   sw_a [32];
    logic [127:0] sw_d [32], sw_m [32];
    logic         sw_conf;
    // flag hits this cycle
    logic [63:0]  hit_hq;  logic [7:0] hit_hqd;  logic [127:0] hit_z;
    // map write requests
    logic [3:0]   bw_en [2];
    logic [6:0]   bw_a [2][4];
    logic [127:0] bw_d [2][4], bw_m [2][4];
    logic         bw_conf;
    // b2 writer state
    logic [1023:0] b2f_d [2];  logic [4:0] b2f_pi [2];  logic [6:0] b2f_tp [2];  logic [3:0] b2f_ct [2];
    logic [1:0]    b2f_n;  logic [1:0] b2_j;  logic b2_ovf;
    wire [88:0]    b2p = pt[b2f_pi[0]];
    wire [2:0]     b2w = pt_lgw(b2p);
    wire [1:0]     b2_nl = (b2w == 3'd2) ? 2'd3 : 2'd1;   // lines - 1
    always_comb begin
        sw_en = '0; sw_conf = 1'b0; hit_hq = '0; hit_hqd = '0; hit_z = '0; bw_conf = 1'b0;
        for (int l = 0; l < 32; l++) begin sw_a[l] = '0; sw_d[l] = '0; sw_m[l] = '0; end
        for (int mp = 0; mp < 2; mp++) begin
            bw_en[mp] = '0;
            for (int m = 0; m < 4; m++) begin bw_a[mp][m] = '0; bw_d[mp][m] = '0; bw_m[mp][m] = '0; end
        end
        // ---------------- fused outputs
        if (fo.v && f_vld_o) begin
            logic [88:0] p;
            p = pt[fo.pi];
            if (fo.hm) begin
                // HQ: px = 16 tp + 4 k + q on the 8 x 8 map, y = 2 tp + (k >> 1), x0 = 4 (k & 1)
                logic [3:0] y, l0;
                y  = 4'(2 * fo.tp + 7'(fo.k[1]));
                l0 = 4'(2 * y + 4'(fo.k[0]));
                for (int pl = 0; pl < 8; pl++)
                    for (int j = 0; j < 2; j++) begin
                        logic [127:0] w;  logic [4:0] ln;  logic [5:0] g;
                        g = 6'(2 * fo.ct + j);
                        for (int q = 0; q < 4; q++) for (int c5 = 0; c5 < 32; c5++)
                            w[32 * q + c5] = f_y[17 * (64 * q + 32 * j + c5) + pl];
                        ln = 5'((l0 + 4'(2 * pl + j)) & 4'hf);
                        if (sw_en[ln]) sw_conf = 1'b1;
                        sw_en[ln] = 1'b1; sw_a[ln] = 8'd128 + 8'(8 * pl) + 8'(g); sw_d[ln] = w; sw_m[ln] = '1;
                        if (|w) hit_hq[8 * pl + g] = 1'b1;
                        if (!y[0]) begin                  // HQD: even pixels x0, x0 + 2 (ox = 2 (k & 1) + q / 2)
                            logic [127:0] wd, wm;  logic [3:0] lg;  logic [1:0] oy;  logic [1:0] t3;
                            wd = '0; wm = '0;
                            oy = 2'(y >> 1);
                            t3 = 2'(g);
                            for (int qq = 0; qq < 2; qq++) for (int c5 = 0; c5 < 32; c5++) begin
                                wd[32 * (2 * fo.k[0] + qq) + c5] = f_y[17 * (64 * (2 * qq) + 32 * j + c5) + pl];
                                wm[32 * (2 * fo.k[0] + qq) + c5] = 1'b1;
                            end
                            lg = 4'({t3, oy}) + rotd(3'(pl));
                            ln = 5'(16 + lg);
                            if (sw_en[ln]) sw_conf = 1'b1;
                            sw_en[ln] = 1'b1; sw_a[ln] = 8'd128 + 8'(2 * pl) + 8'(g >> 2); sw_d[ln] = wd; sw_m[ln] = wm;
`ifndef QBT_MUT_FLAG
                            if (|wd) hit_hqd[pl] = 1'b1;
`endif
                        end
                    end
            end else begin
                // stream (stem / sc r / c2 s_out): flat e = px C + 64 ct, per pixel q one address, 8 lanes
                for (int q = 0; q < 4; q++) begin
                    logic [15:0] px;  logic [23:0] e;  logic [7:0] a;  logic [1:0] pg;
                    px = 16'(fo.tp) * 16 + 16'(fo.k) * 4 + 16'(q);
                    e  = (24'(px) << (6 + pt_lgc(p))) + 24'(fo.ct) * 64;
                    a  = e[15:8];
`ifdef QBT_MUT_SWZ
                    pg = (pt_lgc(p) == 3'd0) ? e[7:6] : e[7:6] ^ h2(a);       // mutant: no swizzle at C = 64
`else
                    pg = e[7:6] ^ h2(a);
`endif
                    for (int col = 0; col < 8; col++) begin
                        logic [127:0] w;
                        for (int i = 0; i < 8; i++) w[16 * i +: 16] = f_y[17 * (64 * q + 8 * col + i) +: 16];
                        if (sw_en[8 * pg + col]) sw_conf = 1'b1;
                        sw_en[8 * pg + col] = 1'b1; sw_a[8 * pg + col] = a; sw_d[8 * pg + col] = w; sw_m[8 * pg + col] = '1;
                    end
                end
                // B1 (b1_next): 2 chunk words of 4 px x 32 ch
                if (pt_b1(p)) begin
                    logic [2:0] lw;  logic [15:0] px0;  logic [15:0] y, x0;
                    lw  = pt_lgw(p);
                    px0 = 16'(fo.tp) * 16 + 16'(fo.k) * 4;
                    y   = px0 >> lw;
                    x0  = px0 & ((16'd1 << lw) - 16'd1);
                    for (int j = 0; j < 2; j++) begin
                        logic [15:0] g, pos;  logic [6:0] line;  logic [1:0] m, pm;  logic [127:0] w;
                        g    = 16'(fo.ct) * 2 + 16'(j);
                        pos  = (g << (lw + 5)) + (x0 << 5);
                        line = 7'(4 * y + (pos >> 9));
                        m    = 2'(pos >> 7);
                        pm   = m + 2'(fsw(line));
                        for (int q = 0; q < 4; q++) w[32 * q +: 32] = f_b[64 * q + 32 * j +: 32];
                        if (bw_en[0][pm]) bw_conf = 1'b1;
                        bw_en[0][pm] = 1'b1; bw_a[0][pm] = line; bw_d[0][pm] = w; bw_m[0][pm] = '1;
                    end
                end
            end
        end
        // ---------------- wide outputs (block 6): px = q + 4 (k >> 3), ch = 64 ct + 8 col + 7 - (k & 7)
        if (wo.v && w_vld_o) begin
            logic [2:0] i0;  logic [1:0] y;
            i0 = 3'd7 - 3'(wo.k);
            y  = 2'(wo.k >> 3);
            if (wo.kind == 3'd5) begin                    // b6.c1 -> Z planes (u8)
                for (int pl = 0; pl < 8; pl++)
                    for (int jj = 0; jj < 2; jj++) begin
                        logic [127:0] wd, wm;  logic [5:0] g;  logic [3:0] lg;  logic [4:0] ln;
                        wd = '0; wm = '0;
                        g  = 6'(2 * wo.ct + jj);
                        for (int q = 0; q < 4; q++) for (int cc = 0; cc < 4; cc++) begin
                            wd[32 * q + 8 * cc + i0] = w_y[19 * (8 * q + 4 * jj + cc) + pl];
                            wm[32 * q + 8 * cc + i0] = 1'b1;
                        end
`ifdef QBT_MUT_ZROT
                        lg = 4'({g[1:0], y}) + {1'b0, 3'(pl)};    // mutant: plane rotation 0..7 (collides)
`else
                        lg = 4'({g[1:0], y}) + rotd(3'(pl));
`endif
                        ln = 5'(16 + lg);
                        if (sw_en[ln]) sw_conf = 1'b1;
                        sw_en[ln] = 1'b1; sw_a[ln] = 8'd144 + 8'(4 * pl) + 8'(g >> 2); sw_d[ln] = wd; sw_m[ln] = wm;
                        if (|wd) hit_z[16 * pl + g] = 1'b1;
                    end
            end else if (wo.kind == 3'd6) begin           // b6.sc -> r lo / hi
                logic [6:0] idx;  logic [7:0] a;
                idx = 7'(wo.ct) * 16 + 7'(wo.k[4:1]);
                a   = idx < 7'd64 ? 8'd64 + 8'(idx) : 8'd128 + 8'(idx);
                for (int q = 0; q < 4; q++)
                    for (int h = 0; h < 2; h++) begin
                        logic [127:0] w;  logic [4:0] ln;
                        for (int cc = 0; cc < 4; cc++) begin
                            logic [18:0] r;
                            r = w_y[19 * (8 * q + 4 * h + cc) +: 19];
                            w[32 * cc +: 16]      = r[15:0];
                            w[32 * cc + 16 +: 16] = 16'($signed(r[18:16]));
                        end
                        ln = 5'(8 * wo.k[0] + 2 * q + h);
                        if (sw_en[ln]) sw_conf = 1'b1;
                        sw_en[ln] = 1'b1; sw_a[ln] = a; sw_d[ln] = w; sw_m[ln] = '1;
                    end
            end else if (wo.kind == 3'd7) begin           // b6.c2 -> s (flat, C = 512) + B1 of block 7 (W 4)
                for (int q = 0; q < 4; q++) begin
                    logic [7:0] a;  logic [1:0] pg;
                    a  = 8'(2 * (q + 4 * y)) + 8'(wo.ct >> 2);
                    pg = 2'(wo.ct) ^ h2(a);
                    for (int col = 0; col < 8; col++) begin
                        logic [4:0] ln;
                        ln = 5'(8 * pg + col);
                        if (sw_en[ln]) sw_conf = 1'b1;
                        sw_en[ln] = 1'b1; sw_a[ln] = a;
                        sw_d[ln] = '0; sw_m[ln] = '0;
                        sw_d[ln][16 * i0 +: 16] = w_y[19 * (8 * q + col) +: 16];
                        sw_m[ln][16 * i0 +: 16] = 16'hffff;
                    end
                end
                for (int jj = 0; jj < 2; jj++) begin
                    logic [5:0] g;  logic [6:0] line;  logic [1:0] pm;  logic [127:0] wd, wm;
                    g = 6'(2 * wo.ct + jj);
                    line = 7'(4 * y + (g >> 2));
                    pm = g[1:0] + 2'(fsw(line));
                    wd = '0; wm = '0;
                    for (int q = 0; q < 4; q++) for (int cc = 0; cc < 4; cc++) begin
                        wd[32 * q + 8 * cc + i0] = w_b[8 * q + 4 * jj + cc];
                        wm[32 * q + 8 * cc + i0] = 1'b1;
                    end
                    if (bw_en[0][pm]) bw_conf = 1'b1;
                    bw_en[0][pm] = 1'b1; bw_a[0][pm] = line; bw_d[0][pm] = wd; bw_m[0][pm] = wm;
                end
            end
        end
        // ---------------- b2 writer: line b2_j of the head capture
        if (b2f_n != 2'd0) begin
            logic [6:0] tp;  logic [3:0] ct;
            tp = b2f_tp[0]; ct = b2f_ct[0];
            for (int m = 0; m < 4; m++) begin
                logic [127:0] w;  logic en;  logic [6:0] line;  logic [1:0] pm;
                w = '0; en = 1'b0; line = '0;
                unique case (b2w)
                    3'd5, 3'd4: begin                     // one row, chunk j = b2_j, macro m = x / 4 (x in the tile)
`ifdef QBT_MUT_B2J
                        line = (b2w == 3'd5) ? 7'(4 * (tp >> 1) + 2 * (2 * ct + (b2_j ^ 1)) + (tp & 1))   // mutant
                                             : 7'(4 * tp + 2 * ct + (b2_j ^ 1));
`else
                        line = (b2w == 3'd5) ? 7'(4 * (tp >> 1) + 2 * (2 * ct + b2_j) + (tp & 1))
                                             : 7'(4 * tp + 2 * ct + b2_j);
`endif
                        en = 1'b1;
                        for (int xq = 0; xq < 4; xq++) for (int c5 = 0; c5 < 32; c5++)
                            w[32 * xq + c5] = b2f_d[0][64 * (4 * m + xq) + 32 * b2_j + c5];
                    end
                    3'd3: begin                           // row y = 2 tp + j, macro m = 2 jj + xh
                        line = 7'(4 * (2 * tp + b2_j) + ct);
                        en = 1'b1;
                        for (int xq = 0; xq < 4; xq++) for (int c5 = 0; c5 < 32; c5++)
                            w[32 * xq + c5] = b2f_d[0][64 * (8 * b2_j + 4 * (m & 1) + xq) + 32 * (m >> 1) + c5];
                    end
                    default: begin                        // W 4: row y = 4 tp + j, macros 2 (ct & 1) + jj
                        line = 7'(4 * (4 * tp + b2_j) + (ct >> 1));
                        en = (m >> 1) == (ct & 1);
                        for (int xq = 0; xq < 4; xq++) for (int c5 = 0; c5 < 32; c5++)
                            w[32 * xq + c5] = b2f_d[0][64 * (4 * b2_j + xq) + 32 * (m & 1) + c5];
                    end
                endcase
                pm = 2'(m) + 2'(fsw(line));
                if (en) begin bw_en[1][pm] = 1'b1; bw_a[1][pm] = line; bw_d[1][pm] = w; bw_m[1][pm] = '1; end
            end
        end
    end

    // ---------------- R4b hook QB_TOP_WBR = 1: the same S write requests built as per-lane-group selects and log
    // rotators (HQ / HQD / Z words go to 16 lanes as a fixed permutation rotated by the tile position; stream and b6.c2
    // pixels to lane groups by the swizzle; HQD / Z / c2 data replicated across the masked-off positions).  The map
    // (B1 / B2) requests stay in the block above.  Conflicts as above (err); under a conflict the data may differ.
    logic [31:0]  wr_en;  logic [7:0] wr_a [32];  logic [127:0] wr_d [32], wr_m [32];  logic wr_conf;
    // rotate 16 lanes up by s (new lane l = old lane l - s mod 16): 128-b words / 8-b addresses
    function automatic logic [2047:0] rup16(input logic [2047:0] x, input logic [3:0] s);
        if (s[0]) x = {x[1919:0], x[2047:1920]};
        if (s[1]) x = {x[1791:0], x[2047:1792]};
        if (s[2]) x = {x[1535:0], x[2047:1536]};
        if (s[3]) x = {x[1023:0], x[2047:1024]};
        return x;
    endfunction
    function automatic logic [127:0] rup8(input logic [127:0] x, input logic [3:0] s);
        if (s[0]) x = {x[119:0], x[127:120]};
        if (s[1]) x = {x[111:0], x[127:112]};
        if (s[2]) x = {x[95:0], x[127:96]};
        if (s[3]) x = {x[63:0], x[127:64]};
        return x;
    endfunction
    logic [63:0]  wr_hq;  logic [7:0] wr_hqd;  logic [127:0] wr_z;
    always_comb begin
        logic [31:0]  ef, ew;  logic [7:0] af [32], aw [32];  logic [127:0] df [32], mf [32], dw [32], mw [32];
        logic         cf, cw;
        ef = '0; ew = '0; cf = 1'b0; cw = 1'b0; wr_hq = '0; wr_hqd = '0; wr_z = '0;
        for (int l = 0; l < 32; l++) begin af[l] = '0; aw[l] = '0; df[l] = '0; mf[l] = '0; dw[l] = '0; mw[l] = '0; end
        // ---- fused
        if (fo.v && f_vld_o) begin
            logic [88:0] p;
            p = pt[fo.pi];
            if (fo.hm) begin
                logic [3:0] y, l0, bq;  logic [1:0] oy;
                logic [2047:0] xw, xd;  logic [127:0] xa, xc;               // 16 lanes x (128-b word, 8-b address)
                y  = 4'(2 * fo.tp + 7'(fo.k[1]));
                l0 = 4'(2 * y + 4'(fo.k[0]));
                oy = 2'(y >> 1);
`ifdef QBT_MUT_WBQ
                bq = {1'b0, 1'b0, oy};                                    // mutant: HQD rotation without the ct term
`else
                bq = {fo.ct[0], 1'b0, oy};                                // HQD base 8 ct[0] + oy
`endif
                for (int pl = 0; pl < 8; pl++)
                    for (int j = 0; j < 2; j++) begin
                        logic [127:0] w, v;  int ix, iz;
                        ix = 2 * pl + j;                                    // HQ word index (lane l0 + ix)
                        iz = 4 * j + int'(rotd(3'(pl)));                    // HQD word index (lane 16 + bq + iz)
                        for (int q = 0; q < 4; q++) for (int c5 = 0; c5 < 32; c5++)
                            w[32 * q + c5] = f_y[17 * (64 * q + 32 * j + c5) + pl];
                        for (int h = 0; h < 2; h++) for (int qq = 0; qq < 2; qq++) for (int c5 = 0; c5 < 32; c5++)
                            v[64 * h + 32 * qq + c5] = f_y[17 * (64 * (2 * qq) + 32 * j + c5) + pl];
                        xw[128 * ix +: 128] = w;  xa[8 * ix +: 8] = 8'd128 + 8'(8 * pl) + 8'(2 * fo.ct + 4'(j));
                        xd[128 * iz +: 128] = v;  xc[8 * iz +: 8] = 8'd128 + 8'(2 * pl) + 8'(fo.ct >> 1);
                        if (|w) wr_hq[8 * pl + 2 * fo.ct + j] = 1'b1;
                        if (|v[63:0] && !y[0]) wr_hqd[pl] = 1'b1;
                    end
                xw = rup16(xw, l0);  xa = rup8(xa, l0);                     // word ix -> lane l0 + ix
                xd = rup16(xd, bq);  xc = rup8(xc, bq);                     // word iz -> lane 16 + bq + iz
                for (int l = 0; l < 16; l++) begin
                    ef[l] = 1'b1; df[l] = xw[128 * l +: 128]; mf[l] = '1; af[l] = xa[8 * l +: 8];
                    ef[16 + l] = !y[0]; df[16 + l] = xd[128 * l +: 128]; af[16 + l] = xc[8 * l +: 8];
                    mf[16 + l] = fo.k[0] ? {64'hffffffffffffffff, 64'd0} : {64'd0, 64'hffffffffffffffff};
                end
            end else begin
                logic [7:0] a [4];  logic [1:0] pg [4];
                for (int q = 0; q < 4; q++) begin
                    logic [15:0] px;  logic [23:0] e;
                    px = 16'(fo.tp) * 16 + 16'(fo.k) * 4 + 16'(q);
                    e  = (24'(px) << (6 + pt_lgc(p))) + 24'(fo.ct) * 64;
                    a[q] = e[15:8];
`ifdef QBT_MUT_SWZ
                    pg[q] = (pt_lgc(p) == 3'd0) ? e[7:6] : e[7:6] ^ h2(a[q]);
`else
                    pg[q] = e[7:6] ^ h2(a[q]);
`endif
                end
                for (int q = 0; q < 4; q++) for (int r = q + 1; r < 4; r++) if (pg[q] == pg[r]) cf = 1'b1;
                for (int G = 0; G < 4; G++)
                    for (int col = 0; col < 8; col++) begin
                        logic [127:0] w;  logic [7:0] aa;  logic en;
                        w = '0; aa = '0; en = 1'b0;
                        for (int q = 0; q < 4; q++)
                            if (pg[q] == 2'(G)) begin
                                en = 1'b1; aa = aa | a[q];
                                for (int i = 0; i < 8; i++) w[16 * i +: 16] = w[16 * i +: 16] | f_y[17 * (64 * q + 8 * col + i) +: 16];
                            end
                        ef[8 * G + col] = en; df[8 * G + col] = w; mf[8 * G + col] = '1; af[8 * G + col] = aa;
                    end
            end
        end
        // ---- wide (block 6)
        if (wo.v && w_vld_o) begin
            logic [2:0] i0;  logic [1:0] y;  logic [127:0] mi;
            i0 = 3'd7 - 3'(wo.k);
            y  = 2'(wo.k >> 3);
            for (int b = 0; b < 128; b++) mi[b] = 3'(b % 8) == i0;          // bit i0 of every byte
            if (wo.kind == 3'd5) begin                                      // b6.c1 -> Z planes
                logic [3:0] bz;  logic [2047:0] xz;  logic [127:0] xa;
                bz = {wo.ct[0], 1'b0, y};
                for (int pl = 0; pl < 8; pl++)
                    for (int jj = 0; jj < 2; jj++) begin
                        logic [127:0] w;  logic [15:0] h;  int iz;
                        iz = 4 * jj + int'(rotd(3'(pl)));
                        for (int q = 0; q < 4; q++) for (int cc = 0; cc < 4; cc++) begin
                            h[4 * q + cc] = w_y[19 * (8 * q + 4 * jj + cc) + pl];
                            for (int i = 0; i < 8; i++) w[32 * q + 8 * cc + i] = h[4 * q + cc];
                        end
                        xz[128 * iz +: 128] = w;  xa[8 * iz +: 8] = 8'd144 + 8'(4 * pl) + 8'(wo.ct >> 1);
                        if (|h) wr_z[16 * pl + 2 * wo.ct + jj] = 1'b1;
                    end
                xz = rup16(xz, bz);  xa = rup8(xa, bz);                     // word iz -> lane 16 + bz + iz
                for (int l = 0; l < 16; l++) begin
                    ew[16 + l] = 1'b1; dw[16 + l] = xz[128 * l +: 128]; mw[16 + l] = mi; aw[16 + l] = xa[8 * l +: 8];
                end
            end else if (wo.kind == 3'd6) begin                             // b6.sc -> r lo / hi
                logic [6:0] idx;  logic [7:0] a;
                idx = 7'(wo.ct) * 16 + 7'(wo.k[4:1]);
                a   = idx < 7'd64 ? 8'd64 + 8'(idx) : 8'd128 + 8'(idx);
                for (int l = 0; l < 16; l++) begin
                    logic [127:0] w;
                    for (int cc = 0; cc < 4; cc++) begin
                        logic [18:0] r;
                        r = w_y[19 * (8 * ((l & 7) >> 1) + 4 * (l & 1) + cc) +: 19];
                        w[32 * cc +: 16] = r[15:0];
                        w[32 * cc + 16 +: 16] = 16'($signed(r[18:16]));
                    end
                    ew[l] = (l >> 3) == int'(wo.k[0]); dw[l] = w; mw[l] = '1; aw[l] = a;
                end
            end else if (wo.kind == 3'd7) begin                             // b6.c2 -> s
                logic [7:0] a [4];  logic [1:0] pg [4];  logic [127:0] m16;
                for (int b = 0; b < 128; b++) m16[b] = 3'(b / 16) == i0;
                for (int q = 0; q < 4; q++) begin
                    a[q]  = 8'(2 * (q + 4 * y)) + 8'(wo.ct >> 2);
                    pg[q] = 2'(wo.ct) ^ h2(a[q]);
                end
                for (int q = 0; q < 4; q++) for (int r = q + 1; r < 4; r++) if (pg[q] == pg[r]) cw = 1'b1;
                for (int G = 0; G < 4; G++)
                    for (int col = 0; col < 8; col++) begin
                        logic [15:0] v;  logic [7:0] aa;  logic en;
                        v = '0; aa = '0; en = 1'b0;
                        for (int q = 0; q < 4; q++)
                            if (pg[q] == 2'(G)) begin en = 1'b1; aa = aa | a[q]; v = v | w_y[19 * (8 * q + col) +: 16]; end
                        ew[8 * G + col] = en; dw[8 * G + col] = {8{v}}; mw[8 * G + col] = m16; aw[8 * G + col] = aa;
                    end
            end
        end
        wr_en = ef | ew;
        wr_conf = cf | cw | ((ef & ew) != '0);
        for (int l = 0; l < 32; l++) begin
            wr_d[l] = ew[l] ? dw[l] : (ef[l] ? df[l] : '0);  wr_m[l] = ew[l] ? mw[l] : (ef[l] ? mf[l] : '0);
            wr_a[l] = ew[l] ? aw[l] : (ef[l] ? af[l] : '0);
        end
    end
    wire [31:0]  u_en = `QB_TOP_WBR ? wr_en : sw_en;
    wire         u_conf = `QB_TOP_WBR ? wr_conf : sw_conf;
    wire [63:0]  u_hq = `QB_TOP_WBR ? wr_hq : hit_hq;
    wire [7:0]   u_hqd = `QB_TOP_WBR ? wr_hqd : hit_hqd;
    wire [127:0] u_z = `QB_TOP_WBR ? wr_z : hit_z;
    // b2 capture FIFO (2 deep) + line counter
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin b2f_n <= '0; b2_j <= '0; b2_ovf <= 1'b0; end
        else begin
            logic pop;
            pop = (b2f_n != 2'd0) && (b2_j == b2_nl);
            b2_j <= (b2f_n != 2'd0) ? (pop ? 2'd0 : b2_j + 2'd1) : 2'd0;
            if (pop) begin b2f_d[0] <= b2f_d[1]; b2f_pi[0] <= b2f_pi[1]; b2f_tp[0] <= b2f_tp[1]; b2f_ct[0] <= b2f_ct[1]; end
            if (b2_vld) begin
                logic [1:0] slot;
                slot = (b2f_n - {1'b0, pop});
                if (slot > 2'd1) b2_ovf <= 1'b1;
                else begin b2f_d[slot] <= b2; b2f_pi[slot] <= bo.pi; b2f_tp[slot] <= bo.tp; b2f_ct[slot] <= bo.ct; end
            end
            b2f_n <= b2f_n - {1'b0, pop} + {1'b0, b2_vld};
        end
    // boundary write registers
    always_ff @(posedge clk) begin
        s_we <= u_en;
        for (int l = 0; l < 32; l++)
            if (`QB_TOP_WBR) begin s_wa[l] <= wr_a[l]; s_wd[l] <= wr_d[l]; s_wm[l] <= wr_m[l]; end
            else begin s_wa[l] <= sw_a[l]; s_wd[l] <= sw_d[l]; s_wm[l] <= sw_m[l]; end
        for (int mp = 0; mp < 2; mp++) begin
            b_we[mp] <= bw_en[mp];
            for (int m = 0; m < 4; m++) begin b_wa[mp][m] <= bw_a[mp][m]; b_wd[mp][m] <= bw_d[mp][m]; b_wm[mp][m] <= bw_m[mp][m]; end
        end
    end

    // ================================================================ slice-flag queue -> qb_act2 flag port (1 / cycle)
    logic [63:0] fp_hq, fs_hq;  logic [7:0] fp_hqd, fs_hqd;  logic [127:0] fp_z, fs_z;
    logic [1:0] quiet [3];
    always_comb begin
        f_clr = 1'b0; f_we = 1'b0; f_nz = 1'b0; f_bank = '0; f_idx = '0;
        if (clr != 3'd0) begin f_clr = 1'b1; f_bank = 2'(clr - 3'd1); end
        else if (fp_hq != '0) begin
            f_we = 1'b1; f_nz = 1'b1; f_bank = 2'd0;
            for (int i = 63; i >= 0; i--) if (fp_hq[i]) f_idx = 7'(i);
        end else if (fp_hqd != '0) begin
            f_we = 1'b1; f_nz = 1'b1; f_bank = 2'd1;
            for (int i = 7; i >= 0; i--) if (fp_hqd[i]) f_idx = 7'(i);
        end else if (fp_z != '0) begin
            f_we = 1'b1; f_nz = 1'b1; f_bank = 2'd2;
            for (int i = 127; i >= 0; i--) if (fp_z[i]) f_idx = 7'(i);
        end
    end
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin clr <= '0; fp_hq <= '0; fs_hq <= '0; fp_hqd <= '0; fs_hqd <= '0; fp_z <= '0; fs_z <= '0; quiet <= '{2'd0, 2'd0, 2'd0}; end
        else if (go) begin clr <= 3'd3; fp_hq <= '0; fs_hq <= '0; fp_hqd <= '0; fs_hqd <= '0; fp_z <= '0; fs_z <= '0; quiet <= '{2'd0, 2'd0, 2'd0}; end
        else begin
            logic [63:0] nh;  logic [7:0] nd;  logic [127:0] nz;
            if (clr != 3'd0) clr <= clr - 3'd1;
            nh = fp_hq; nd = fp_hqd; nz = fp_z;
            if (f_we) unique case (f_bank)
                2'd0: nh[f_idx[5:0]] = 1'b0;
                2'd1: nd[f_idx[2:0]] = 1'b0;
                default: nz[f_idx] = 1'b0;
            endcase
            fp_hq  <= nh | (u_hq & ~fs_hq);   fs_hq  <= fs_hq | u_hq;
            fp_hqd <= nd | (u_hqd & ~fs_hqd); fs_hqd <= fs_hqd | u_hqd;
            fp_z   <= nz | (u_z & ~fs_z);     fs_z   <= fs_z | u_z;
            for (int bk = 0; bk < 3; bk++) begin
                logic act_;
                act_ = ((f_we || f_clr) && f_bank == 2'(bk)) || (bk == 0 ? u_hq != '0 : bk == 1 ? u_hqd != '0 : u_z != '0);
                quiet[bk] <= act_ ? 2'd0 : (quiet[bk] == 2'd3 ? 2'd3 : quiet[bk] + 2'd1);
            end
        end
    for (genvar bk = 0; bk < 3; bk++) begin : g_fq
        assign fl_quiet[bk] = quiet[bk] >= 2'd2;
    end

    // ================================================================ R3b: sequencer + params path (hook, R3B = 1)
    // (t2_c / pf_c / pw_c declared before the core instance: R4, DC needs declaration before use)
    logic          seq_err, prm_err;
    if (R3B) begin : g_r3b
        logic [5183:0] pf_s;  logic [5055:0] pw_s;  logic [1087:0] t2_s;
        stp_t fe_, we_;  cev_t ce_, cu_;
        assign fe_ = fdl[D];  assign we_ = wdl[D];  assign ce_ = cdl[D];  assign cu_ = cdl[D + 2];
        if (`QB_SEQ_RT == 0) begin : g_s0
        qb_seq #(.NT(`QB_SEQ_NT), .NLT(`QB_SEQ_NLT), .DSCM(`QB_SEQ_DSCM)) u_seq (
            .clk, .rst_n, .go, .run, .now, .h_we, .h_sel, .h_addr, .h_d(h_data[95:0]), .pt, .done, .p_fire(s_pfire),
            .p_pi(s_ppi), .tgo(s_tgo), .l_pos0, .l_pos1, .fl_quiet, .l_ok(s_lok), .l_seq0(s_lseq0), .l_seq1(s_lseq1),
            .d_vld, .d_eot, .fs_hq, .fs_hqd, .fs_z, .c_fire(s_cfire), .c_cmp(s_ccmp), .c_pi(s_cpi), .c_tp(s_ctp),
            .c_ct(s_cct), .f_fire(s_ffire), .f_job(s_fjob), .w_fire(s_wfire), .w_job(s_wjob), .err(seq_err));
        end else begin : g_rt
        // R4b: retimed sequencer (hw/rtl/qb_seq_rt.sv), same cycle behaviour; in simulation the R3b qb_seq runs in
        // lockstep on the same inputs and any output difference sets err (QBT_NOLOCK: off, for mutant runs)
        logic seq_err_rt, lk_err;
        qb_seq_rt #(.NT(`QB_SEQ_NT), .NLT(`QB_SEQ_NLT), .LSW(`QB_SEQ_LSW)) u_seq (
            .clk, .rst_n, .go, .run, .now, .h_we, .h_sel, .h_addr, .h_d(h_data[95:0]), .pt, .done, .p_fire(s_pfire),
            .p_pi(s_ppi), .tgo(s_tgo), .l_pos0, .l_pos1, .fl_quiet, .l_ok(s_lok), .l_seq0(s_lseq0), .l_seq1(s_lseq1),
            .d_vld, .d_eot, .fs_hq, .fs_hqd, .fs_z, .c_fire(s_cfire), .c_cmp(s_ccmp), .c_pi(s_cpi), .c_tp(s_ctp),
            .c_ct(s_cct), .f_fire(s_ffire), .f_job(s_fjob), .w_fire(s_wfire), .w_job(s_wjob), .err(seq_err_rt));
`ifndef SYNTHESIS
`ifndef QBT_NOLOCK
        logic [1:0]  r_pfire, r_tgo, r_lok;  logic [4:0] r_ppi [2];  logic [15:0] r_lseq0, r_lseq1, r_fjob, r_wjob;
        logic        r_cfire, r_ccmp, r_ffire, r_wfire, r_err;  logic [4:0] r_cpi;  logic [6:0] r_ctp;  logic [3:0] r_cct;
        qb_seq #(.NT(`QB_SEQ_NT), .NLT(`QB_SEQ_NLT), .DSCM(0)) u_ref (
            .clk, .rst_n, .go, .run, .now, .h_we, .h_sel, .h_addr, .h_d(h_data[95:0]), .pt, .done, .p_fire(r_pfire),
            .p_pi(r_ppi), .tgo(r_tgo), .l_pos0, .l_pos1, .fl_quiet, .l_ok(r_lok), .l_seq0(r_lseq0), .l_seq1(r_lseq1),
            .d_vld, .d_eot, .fs_hq, .fs_hqd, .fs_z, .c_fire(r_cfire), .c_cmp(r_ccmp), .c_pi(r_cpi), .c_tp(r_ctp),
            .c_ct(r_cct), .f_fire(r_ffire), .f_job(r_fjob), .w_fire(r_wfire), .w_job(r_wjob), .err(r_err));
        int nlk = 0;
        wire lk_d = s_pfire != r_pfire || (s_pfire[0] && s_ppi[0] != r_ppi[0]) || (s_pfire[1] && s_ppi[1] != r_ppi[1]) ||
                    s_tgo != r_tgo || s_lok != r_lok || (s_lok[0] && s_lseq0 != r_lseq0) || (s_lok[1] && s_lseq1 != r_lseq1) ||
                    s_cfire != r_cfire || (s_cfire && {s_ccmp, s_cpi, s_ctp, s_cct} != {r_ccmp, r_cpi, r_ctp, r_cct}) ||
                    s_ffire != r_ffire || (s_ffire && s_fjob != r_fjob) || s_wfire != r_wfire || (s_wfire && s_wjob != r_wjob);
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) lk_err <= 1'b0;
            else if (run && lk_d) begin
                lk_err <= 1'b1;
                nlk <= nlk + 1;
                if (nlk < 5) $display("QB_SEQ_LOCKSTEP mismatch now %0d: pfire %b/%b tgo %b/%b lok %b/%b cfire %b/%b ffire %b/%b fjob %h/%h wfire %b/%b",
                                      now, s_pfire, r_pfire, s_tgo, r_tgo, s_lok, r_lok, s_cfire, r_cfire, s_ffire, r_ffire,
                                      s_fjob, r_fjob, s_wfire, r_wfire);
            end
`else
        assign lk_err = 1'b0;
`endif
`else
        assign lk_err = 1'b0;
`endif
        assign seq_err = seq_err_rt | lk_err;
        end
        qb_prm #(.HSEL(HSEL), .NFF(`QB_PRM_NFF), .NFW(`QB_PRM_NFW), .NFT(`QB_PRM_NFT)) u_prm (
            .clk, .rst_n, .go, .h_we, .h_sel, .h_addr, .h_d(h_data[1295:0]),
            .u_early({ce_.v && ce_.cmp, we_.v && we_.k == 5'd0, fe_.v && (fe_.hm ? fe_.k == 5'd3 : fe_.k == 5'd0)}),
            .u_use({cu_.v && cu_.cmp, wp.v && wp.k == 5'd0, fp.v && (fp.hm ? fp.k == 5'd3 : fp.k == 5'd0)}),
            .tag_f({fp.hm ? 4'd0 : fp.ct, fp.pi}), .tag_w({wp.ct, wp.pi}), .tag_t({cu_.ct, cu_.pi}),
            .pf(pf_s), .pw(pw_s), .t2(t2_s), .err(prm_err));
        wire [95:0] ptf = pt[fp.pi], ptw = pt[wp.pi];
        assign pf_c = {ptf[93:89], pf_s};
        assign pw_c = {ptw[91:89], pw_s};
        assign t2_c = t2_s;
    end else begin : g_r3a
        assign pf_c = pf_q;  assign pw_c = pw_q;  assign t2_c = t2_q;
        assign seq_err = 1'b0;  assign prm_err = 1'b0;
        assign s_pfire = '0; assign s_tgo = '0; assign s_lok = '0; assign s_ppi[0] = '0; assign s_ppi[1] = '0;
        assign s_lseq0 = '0; assign s_lseq1 = '0; assign s_fjob = '0; assign s_wjob = '0; assign s_cfire = 1'b0;
        assign s_ccmp = 1'b0; assign s_ffire = 1'b0; assign s_wfire = 1'b0; assign s_cpi = '0; assign s_ctp = '0;
        assign s_cct = '0;
    end

    // ================================================================ checks (sticky error)
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) err <= 1'b0;
        else err <= err | seq_err | prm_err | a_err | s_conf | rd_conf | f_rconf | (|s_rwc) | (|b_rwc) | u_conf | bw_conf | b2_ovf | f_ovl | w_ovl |
                   (b2_vld && !(bo.v && bo.cmp)) | (f_vld_o && !fo.v) | (w_vld_o && !wo.v) |
                   (fo.v && !f_vld_o) | (wo.v && !w_vld_o);

    // ================================================================ bench taps
    assign dbg_ftp = fo.tp;  assign wb_fct = fo.ct;  assign wb_fk = fo.k[1:0];
    assign wb_fv = f_vld_o;  assign wb_fpi = fo.pi;  assign wb_fy = f_y;  assign dbg_fb = f_b;
    assign dbg_wv = w_vld_o;  assign dbg_wpi = wo.pi;  assign dbg_wy = w_y;  assign dbg_wb = w_b;
    assign dbg_bv = b2_vld;   assign dbg_bpi = bo.pi;  assign dbg_b2 = b2;
    assign {dbg_av, ae_ctx, ae_eot, dbg_af, dbg_aneg, dbg_astem, dbg_ag3n} = {a_vld, a_ctx, a_eot, a_first, a_neg, a_stem, a_g3n};
    assign dbg_apl = a_plane;  assign dbg_act_ct = a_ct;  assign dbg_ach = a_chunk;  assign dbg_atile = a_tile;
    assign dbg_act = a_act;  assign ae_pic0 = cpi[0];  assign ae_pic1 = cpi[1];
endmodule

// ================================================================================================ helpers
// (QB_TECH: qbt_rf2p / qbt_rfsp come from hw/tech/qb_mem_tech.sv)
module qbt_dreg #(parameter int W = 1) (input logic clk, input logic [W-1:0] d, output logic [W-1:0] q);
    always_ff @(posedge clk) q <= d;
endmodule

`ifndef QB_TECH
// behavioural rf_2p (1R + 1W, bit-write mask): ren / ra / we / wa / wd / wm are the (registered) macro inputs of this
// cycle; q = read data from the cycle after a read.  Read and write of one address in one cycle -> q = X (rf_2p_adv).
module qbt_rf2p #(parameter int W = 128, parameter int N = 256) (
    input  logic                 clk, ren, we,
    input  logic [$clog2(N)-1:0] ra, wa,
    input  logic [W-1:0]         wd, wm,
    output logic [W-1:0]         q,
    output logic                 conf
);
    logic [W-1:0] mem [N];
    assign conf = ren && we && ra == wa;
    always_ff @(posedge clk) begin
        if (ren) q <= conf ? 'x : mem[ra];
        if (we) mem[wa] <= (mem[wa] & ~wm) | (wd & wm);
    end
endmodule

// behavioural rf_sp (1RW): a write (host load) or a read per cycle
module qbt_rfsp #(parameter int W = 128, parameter int N = 128) (
    input  logic                 clk, ren, we,
    input  logic [$clog2(N)-1:0] a,
    input  logic [W-1:0]         wd,
    output logic [W-1:0]         q
);
    logic [W-1:0] mem [N];
    always_ff @(posedge clk) begin
        if (we) mem[a] <= wd;
        else if (ren) q <= mem[a];
    end
endmodule
`endif
