// Tile-level bench of qb_core (16 x 8) against the compiler's dataflow model (Verilator --binary).
// +dir=<export_core.py image dir>: stim.txt drives every port each cycle; exp_b2 / exp_f / exp_w are compared in order
// whenever b2_vld / f_vld_o / w_vld_o is high (every output word: b2 bit, fused lane (s_out / r / u8, b1_next), wide
// lane (y, b)).  Prints one QB_CORE line per pass and a QB_CORE_TB PASS / FAIL summary.
module tb_qb_core;
    localparam int ROWS = 16, COLS = 8, KB = 36, MWF = 28;
    localparam int NLF = 4 * COLS * 8, NLW = 4 * COLS, NP = 64;
    logic clk = 0, rst_n;
    logic [COLS*KB*8-1:0]          cd;
    logic [9:0]                    ctl;
    logic [ROWS*KB*8-1:0]          act;
    logic [COLS*8*17-1:0]          t2;
    logic [ROWS*COLS*8-1:0]        b2;
    logic                          b2_vld, f_vld, f_src, f_sh, p_ld, f_vld_o, w_vld, w_sh, w_ld, w_vld_o;
    logic [COLS*8*(37+MWF+16)+4:0] pf;
    logic [NLF*17-1:0]             s_rd, f_y;
    logic [NLF-1:0]                f_b;
    logic [COLS*8*79+2:0]          pw;
    logic [NLW*19-1:0]             w_r, w_y;
    logic [NLW-1:0]                w_b;
    logic [3:0]                    fctl;
    logic [2:0]                    wctl;

    // pnr_slice2.md options of qb_core (default 0 = R1): -DQBC_CREG=1 -DQBC_WTP=1 -DQBC_FTP=1 -DQBC_PPOP=1 (QBC_DEFS)
`ifndef QBC_CREG
`define QBC_CREG 0
`endif
`ifndef QBC_WTP
`define QBC_WTP 0
`endif
`ifndef QBC_FTP
`define QBC_FTP 0
`endif
`ifndef QBC_BRG
`define QBC_BRG 8
`endif
`ifndef QBC_PPOP
`define QBC_PPOP 0
`endif
    qb_core #(.ROWS(ROWS), .COLS(COLS), .KB(KB), .MWF(MWF), .CREG(`QBC_CREG), .WTP(`QBC_WTP), .FTP(`QBC_FTP),
              .PPOP(`QBC_PPOP), .BRG(`QBC_BRG)) dut (.*);
    assign {p_ld, f_sh, f_src, f_vld} = fctl;
    assign {w_ld, w_sh, w_vld} = wctl;

    int fs, fb2, ff, fw, n, pi, rc, k, e, nerr_tot, nchk_tot;
    int cb2 [NP], eb2 [NP], cf [NP], ef [NP], cw [NP], ew [NP];
    logic [ROWS*COLS*8-1:0] xb2;
    logic [NLF*17-1:0]      xfy;
    logic [NLF-1:0]         xfb;
    logic [NLW*19-1:0]      xwy;
    logic [NLW-1:0]         xwb;
    string dir;

    initial begin
        if (!$value$plusargs("dir=%s", dir)) $fatal(1, "need +dir=");
        fs  = $fopen({dir, "/stim.txt"}, "r");
        fb2 = $fopen({dir, "/exp_b2.txt"}, "r");
        ff  = $fopen({dir, "/exp_f.txt"}, "r");
        fw  = $fopen({dir, "/exp_w.txt"}, "r");
        if (fs == 0 || fb2 == 0 || ff == 0 || fw == 0) $fatal(1, "cannot open vectors in %s", dir);
        for (int i = 0; i < NP; i++) begin cb2[i] = 0; eb2[i] = 0; cf[i] = 0; ef[i] = 0; cw[i] = 0; ew[i] = 0; end
        n = 0; nerr_tot = 0; nchk_tot = 0;
        while ($fscanf(fs, "%h %h %h %h %h %h %h %h %h %h\n", ctl, cd, act, t2, fctl, pf, s_rd, wctl, pw, w_r) == 10) begin
            rst_n = (n >= 1);
            #5 clk = 1;
            #1;
            if (b2_vld === 1'b1) begin
                if ($fscanf(fb2, "%d %h\n", pi, xb2) != 2) begin $display("QB_CORE extra b2 word at cycle %0d", n); nerr_tot++; end
                else begin
                    cb2[pi] += ROWS * COLS * 8;
                    e = $countones(b2 ^ xb2);
                    if ($isunknown(b2)) e = ROWS * COLS * 8;
                    eb2[pi] += e;
                    if (e != 0 && eb2[pi] == e) $display("MISMATCH b2 pass %0d cycle %0d: %0d bits", pi, n, e);
                end
            end
            if (f_vld_o === 1'b1) begin
                if ($fscanf(ff, "%d %h %h\n", pi, xfy, xfb) != 3) begin $display("QB_CORE extra fused word at cycle %0d", n); nerr_tot++; end
                else begin
                    cf[pi] += NLF;
                    for (k = 0; k < NLF; k++)
                        if (f_y[17*k +: 17] !== xfy[17*k +: 17] || f_b[k] !== xfb[k]) begin
                            ef[pi]++;
                            if (ef[pi] <= 3) $display("MISMATCH fused pass %0d cycle %0d lane %0d: y %h b %b exp %h %b", pi,
                                                      n, k, f_y[17*k +: 17], f_b[k], xfy[17*k +: 17], xfb[k]);
                        end
                end
            end
            if (w_vld_o === 1'b1) begin
                if ($fscanf(fw, "%d %h %h\n", pi, xwy, xwb) != 3) begin $display("QB_CORE extra wide word at cycle %0d", n); nerr_tot++; end
                else begin
                    cw[pi] += NLW;
                    for (k = 0; k < NLW; k++)
                        if (w_y[19*k +: 19] !== xwy[19*k +: 19] || w_b[k] !== xwb[k]) begin
                            ew[pi]++;
                            if (ew[pi] <= 3) $display("MISMATCH wide pass %0d cycle %0d lane %0d: y %h b %b exp %h %b", pi,
                                                      n, k, w_y[19*k +: 19], w_b[k], xwy[19*k +: 19], xwb[k]);
                        end
                end
            end
            #4 clk = 0;
            n++;
        end
        // every expected word must have been produced
        if ($fscanf(fb2, "%d %h\n", pi, xb2) == 2) begin $display("QB_CORE missing b2 words (pass %0d)", pi); nerr_tot++; end
        if ($fscanf(ff, "%d %h %h\n", pi, xfy, xfb) == 3) begin $display("QB_CORE missing fused words (pass %0d)", pi); nerr_tot++; end
        if ($fscanf(fw, "%d %h %h\n", pi, xwy, xwb) == 3) begin $display("QB_CORE missing wide words (pass %0d)", pi); nerr_tot++; end
        for (int i = 0; i < NP; i++)
            if (cb2[i] + cf[i] + cw[i] > 0) begin
                $display("QB_CORE pass %0d b2_bits %0d err %0d fused_words %0d err %0d wide_words %0d err %0d", i,
                         cb2[i], eb2[i], cf[i], ef[i], cw[i], ew[i]);
                nerr_tot += eb2[i] + ef[i] + ew[i];
                nchk_tot += cb2[i] + cf[i] + cw[i];
            end
        $display("QB_CORE_TB %s cycles %0d checked %0d errors %0d %s", dir, n, nchk_tot, nerr_tot,
                 (nerr_tot == 0 && nchk_tot > 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
