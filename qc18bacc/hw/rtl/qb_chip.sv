// qb_chip: QC18B-ACC, image to logits (R3c): qb_top (R3B = 1 sequencer + params bank, HSEL = 1) + qb_head (pool + FC).
//
// Host port (synchronous, one write per cycle, no bus protocol; results/r3c.md section 2):
//   h_we, h_sel[4:0], h_addr[10:0], h_data[5188:0]: write one word.
//     h_sel 0..15 -> qb_top (0 weight row 2 304 b, 1 params bank row 1 296 b, 2 image line 512 b (IMG, 128 lines),
//                    3 pass table, 4 / 5 context pass lists, 10 load-permission entries, 11 tile descriptors,
//                    12..14 params fetch lists, 15 counts; h_addr[9:0])
//     h_sel 16    -> FC macro row (256 b, h_addr 0..1 631)
//     h_sel 17    -> head configuration word h_addr: 0 pool m0, 1 pool sh, 2 last pass, 3 last-pass fused outputs,
//                    4 stem pass, 5 stem tile ends, 6 classes, 7 FC rows (hw/tb/export_top3.py head.txt)
//   h_go: start the image held in IMG (allowed while st_idle; the program stays loaded across images).
//   st_idle: no image in the engine (set the cycle after the last fused write-back request of the last pass, i.e. in
//            the cycle of that last macro write; h_go may be given in that cycle).
//   st_img_free: IMG may be written (no image in flight, or the running image's stem has ended all its tiles); the
//            next image is loaded while the current one computes, so IMG is single-buffered (r3c.md: no double buffer).
//   lo_vld / lo_idx / lo_val: logits stream, one int32 class logit per valid (IntBin2 logit = lo_val x fscale[idx],
//            host side); the head of image i delivers during image i + 1.
//   err: sticky (qb_top checks, head conflicts, host contract: h_go while busy, IMG write while not free).
// R4b: define QB_HEAD_HP (default 0) selects qb_head's two-stage FC tree (same cycles).
`ifndef QB_HEAD_HP
`define QB_HEAD_HP 0
`endif
// R5e: define QB_HEAD_FW (default 256) = qb_head FC weight port FW.  128 (results/r5e_fc.md): FC rows 0..2047 are
// written with h_sel 16 at h_addr, rows 2048.. with h_sel 18 at h_addr (row = {h_sel == 18, h_addr}); head
// configuration word 7 (FC rows) is 12 b.
`ifndef QB_HEAD_FW
`define QB_HEAD_FW 256
`endif
// R6a: define QB_HPW = W (undefined by default: the wide port above) = narrow host port (results/r6a.md): h_data[W-1:0]
// + h_lane[4:0], one macro word per write: h_sel 0 weight row h_addr, lane 0..15 (144 b each; 16 writes per row),
// h_sel 1 params bank row, lane 0..8 (144 b; 9 writes), h_sel 2 IMG line, lane 0..3 (128 b; 4 writes), every other
// select one write as before (<= 128 b, lane 0).  W >= 144, QB_HEAD_FW = 128.  The write inputs pass one IO register
// stage here (h_go does not: h_go / st_* / image timing are unchanged); weights / IMG / params then go through
// registered per-group stages in qb_top / qb_prm (qb_top header).  A write lands at most HL = 10 cycles after it is
// given; h_go within HL cycles of a host write sets err.  The IMG contract (write only while st_img_free) is unchanged;
// an IMG write landing in a stem IMG read cycle sets err (qb_top).
`ifdef QB_HPW
`define QB_HPW_V `QB_HPW
`else
`define QB_HPW_V 0
`endif
module qb_chip #(parameter int DIST = 1, parameter int AP = 1, parameter int HPW = `QB_HPW_V) (
    input  logic          clk, rst_n,
    input  logic          h_we,
    input  logic [4:0]    h_sel,
    input  logic [10:0]   h_addr,
    input  logic [(HPW > 0 ? HPW : 5189) - 1:0] h_data,
`ifdef QB_HPW
    input  logic [4:0]    h_lane,
`endif
    input  logic          h_go,
    output logic          st_idle, st_img_free, st_head_busy,
    output logic          lo_vld,
    output logic [6:0]    lo_idx,
    output logic [31:0]   lo_val,
    output logic          err,
    output logic [15:0]   now
);
    // ---------------------------------------------------------------- host port (R6a: narrow port IO register)
    logic          i_we, hp_err;
    logic [4:0]    i_sel;
    logic [10:0]   i_addr;
    logic [5188:0] i_data;
    if (HPW == 0) begin : g_hpw
        assign i_we = h_we;  assign i_sel = h_sel;  assign i_addr = h_addr;  assign i_data = h_data;  assign hp_err = 1'b0;
    end else begin : g_hpn
        localparam int HL = 10;                                          // IO register + weight chain (8) + macro
        logic [HPW-1:0] q_d;  logic [4:0] q_l;  logic [3:0] hcnt;
`ifdef QB_HPW
        wire [4:0] lane = h_lane;
`else
        wire [4:0] lane = 5'd0;
`endif
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) begin i_we <= 1'b0; hcnt <= 4'(HL); end
            else begin
                i_we <= h_we;
                hcnt <= h_we ? 4'd0 : (hcnt == 4'(HL) ? hcnt : hcnt + 4'd1);
            end
        always_ff @(posedge clk) if (h_we) begin i_sel <= h_sel; i_addr <= h_addr; q_d <= h_data; q_l <= lane; end
        assign i_data = 5189'({q_l, q_d});
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) hp_err <= 1'b0; else hp_err <= hp_err | (h_go && (h_we || hcnt < 4'(HL - 1)));
    end
    // ---------------------------------------------------------------- head configuration
    logic [30:0] c_m0;  logic [5:0] c_sh;  logic [4:0] c_last, c_stem;  logic [7:0] c_nfo, c_nst;
    localparam int FW = `QB_HEAD_FW, FAW = FW == 128 ? 12 : 11;
    initial if (HPW > 0 && (HPW < FW || HPW < 144)) $fatal(1, "qb_chip: QB_HPW must be >= 144 and >= QB_HEAD_FW");
    logic [6:0]  c_ncls;  logic [FAW-1:0] c_nrows;
    always_ff @(posedge clk)
        if (i_we && i_sel == 5'd17) unique case (i_addr[2:0])
            3'd0: c_m0 <= i_data[30:0];
            3'd1: c_sh <= i_data[5:0];
            3'd2: c_last <= i_data[4:0];
            3'd3: c_nfo <= i_data[7:0];
            3'd4: c_stem <= i_data[4:0];
            3'd5: c_nst <= i_data[7:0];
            3'd6: c_ncls <= i_data[6:0];
            default: c_nrows <= i_data[FAW-1:0];
        endcase

    // ---------------------------------------------------------------- engine
    logic t_err, wb_fv, dbg_wv, dbg_bv, dbg_av, ae_ctx, ae_eot, dbg_af, dbg_aneg, dbg_astem, dbg_ag3n;
    logic [4:0] wb_fpi, dbg_wpi, dbg_bpi, ae_pic0, ae_pic1;
    logic [6:0] dbg_ftp;  logic [3:0] wb_fct;  logic [1:0] wb_fk;
    logic [4351:0] wb_fy;  logic [255:0] dbg_fb;  logic [607:0] dbg_wy;  logic [31:0] dbg_wb;  logic [1023:0] dbg_b2;
    logic [2:0] dbg_apl, dbg_act_ct;  logic [3:0] dbg_ach;  logic [5:0] dbg_atile;  logic [4607:0] dbg_act;
    logic [4095:0] dbg_sq;
`ifdef QBC_MUT_HSEL
    localparam bit HS = 1'b0;                                            // mutant: R3a/R3b host address muxing
`else
    localparam bit HS = 1'b1;
`endif
    qb_top #(.DIST(DIST), .AP(AP), .R3B(1), .HSEL(HS), .HPW(HPW)) u_top (
        .clk, .rst_n, .go(h_go), .h_we(i_we && !i_sel[4]), .h_sel(i_sel[3:0]), .h_addr(i_addr[9:0]), .h_data(i_data), .now,
        .err(t_err), .wb_fv, .dbg_wv, .dbg_bv, .wb_fpi, .dbg_wpi, .dbg_bpi, .dbg_ftp, .wb_fct, .wb_fk, .wb_fy,
        .dbg_fb, .dbg_wy, .dbg_wb, .dbg_b2, .dbg_av, .ae_ctx, .ae_eot, .dbg_af, .dbg_aneg, .dbg_astem, .dbg_ag3n,
        .dbg_apl, .dbg_act_ct, .dbg_ach, .dbg_atile, .dbg_act, .ae_pic0, .ae_pic1, .dbg_sa(8'd0), .dbg_sq);

    // image in flight: from h_go to the last fused write-back of the last pass (c_nfo of them)
    logic       busy, img_free;
    logic [7:0] nfo, nst;
    wire        last_fo = wb_fv && wb_fpi == c_last;
    wire        stem_eot = ae_eot && (ae_ctx ? ae_pic1 : ae_pic0) == c_stem;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin busy <= 1'b0; img_free <= 1'b1; nfo <= '0; nst <= '0; end
        else if (h_go) begin busy <= 1'b1; img_free <= 1'b0; nfo <= '0; nst <= '0; end
        else begin
            if (busy && last_fo) begin
                if (nfo + 8'd1 == c_nfo) begin busy <= 1'b0; nfo <= '0; end else nfo <= nfo + 8'd1;
            end
`ifndef QBC_MUT_IMGF
            if (busy && stem_eot) begin
                if (nst + 8'd1 == c_nst) img_free <= 1'b1;
                nst <= nst + 8'd1;
            end
`else
            img_free <= 1'b1;                                            // mutant: IMG reported free during the stem
`endif
        end
    assign st_idle = !busy;
    assign st_img_free = img_free || !busy;

    // ---------------------------------------------------------------- head
    logic h_err, pool_done, fc_busy;
    logic          fc_we;
    logic [FAW-1:0] fc_a;
    if (FW == 128) begin : g_fc128                                       // rows 2048.. via h_sel 18
        assign fc_we = i_we && (i_sel == 5'd16 || i_sel == 5'd18);
`ifdef QBC_MUT_FHI
        assign fc_a  = {1'b0, i_addr};                                   // mutant: upper FC rows overwrite rows 0..
`else
        assign fc_a  = {i_sel == 5'd18, i_addr};
`endif
    end else begin : g_fc256
        assign fc_we = i_we && i_sel == 5'd16;
        assign fc_a  = i_addr;
    end
    qb_head #(.HP(`QB_HEAD_HP), .FW(FW)) u_head (
        .clk, .rst_n, .fc_we, .h_addr(fc_a), .h_d(i_data[FW-1:0]), .c_m0, .c_sh, .c_last, .c_ncls,
        .c_nrows, .f_v(wb_fv), .f_pi(wb_fpi), .f_ct(wb_fct), .f_k(wb_fk), .f_y(wb_fy), .lo_vld, .lo_idx, .lo_val,
        .pool_done, .fc_busy, .busy(st_head_busy), .err(h_err));

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) err <= 1'b0;
        else err <= err | t_err | h_err | hp_err | (h_go && busy) | (h_we && h_sel == 5'd2 && !st_img_free);
endmodule
