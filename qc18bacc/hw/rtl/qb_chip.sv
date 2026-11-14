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
module qb_chip #(parameter int DIST = 1, parameter int AP = 1) (
    input  logic          clk, rst_n,
    input  logic          h_we,
    input  logic [4:0]    h_sel,
    input  logic [10:0]   h_addr,
    input  logic [5188:0] h_data,
    input  logic          h_go,
    output logic          st_idle, st_img_free, st_head_busy,
    output logic          lo_vld,
    output logic [6:0]    lo_idx,
    output logic [31:0]   lo_val,
    output logic          err,
    output logic [15:0]   now
);
    // ---------------------------------------------------------------- head configuration
    logic [30:0] c_m0;  logic [5:0] c_sh;  logic [4:0] c_last, c_stem;  logic [7:0] c_nfo, c_nst;
    logic [6:0]  c_ncls;  logic [10:0] c_nrows;
    always_ff @(posedge clk)
        if (h_we && h_sel == 5'd17) unique case (h_addr[2:0])
            3'd0: c_m0 <= h_data[30:0];
            3'd1: c_sh <= h_data[5:0];
            3'd2: c_last <= h_data[4:0];
            3'd3: c_nfo <= h_data[7:0];
            3'd4: c_stem <= h_data[4:0];
            3'd5: c_nst <= h_data[7:0];
            3'd6: c_ncls <= h_data[6:0];
            default: c_nrows <= h_data[10:0];
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
    qb_top #(.DIST(DIST), .AP(AP), .R3B(1), .HSEL(HS)) u_top (
        .clk, .rst_n, .go(h_go), .h_we(h_we && !h_sel[4]), .h_sel(h_sel[3:0]), .h_addr(h_addr[9:0]), .h_data, .now,
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
    qb_head #(.HP(`QB_HEAD_HP)) u_head (
        .clk, .rst_n, .fc_we(h_we && h_sel == 5'd16), .h_addr, .h_d(h_data[255:0]), .c_m0, .c_sh, .c_last, .c_ncls,
        .c_nrows, .f_v(wb_fv), .f_pi(wb_fpi), .f_ct(wb_fct), .f_k(wb_fk), .f_y(wb_fy), .lo_vld, .lo_idx, .lo_val,
        .pool_done, .fc_busy, .busy(st_head_busy), .err(h_err));

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) err <= 1'b0;
        else err <= err | t_err | h_err | (h_go && busy) | (h_we && h_sel == 5'd2 && !st_img_free);
endmodule
