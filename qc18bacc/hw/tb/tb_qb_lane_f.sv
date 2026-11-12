// Self-check bench of qb_lane_f (Verilator --binary).  Define MW (multiplier port width, = QBF_MW of the DUT).
// Reads +stim=<file> (per cycle: ctl{rst_n, vld, relu, sgn} acc bias lo hi m sh h sv rmode omode t, hex) and
// +exp=<file> (per cycle after the clock edge: <defined 0/1> <vld_o> <y_o hex> <b_o>), written by gen_f.py;
// prints QB_TB PASS / FAIL.
module tb_qb_lane_f;
    localparam int MW = `QBF_MW;
    logic clk = 0, rst_n, vld, relu, sgn, vld_o, b_o, ev, eb;
    logic signed [19:0] acc;
    logic signed [15:0] bias, lo, hi, h, t;
    logic        [MW-1:0] m;
    logic        [3:0]  sh, ctl;
    logic signed [16:0] sv, y_o, ey;
    logic        [1:0]  rmode, omode;
    int fs, fe, n, nchk, nerr, d;
    string sf, ef;

`ifndef QBF_DUT
`define QBF_DUT qb_lane_f
`endif
    `QBF_DUT dut (.*);

    initial begin
        if (!$value$plusargs("stim=%s", sf) || !$value$plusargs("exp=%s", ef)) $fatal(1, "need +stim= +exp=");
        fs = $fopen(sf, "r"); fe = $fopen(ef, "r");
        if (fs == 0 || fe == 0) $fatal(1, "cannot open stim / exp");
        n = 0; nchk = 0; nerr = 0;
        while ($fscanf(fs, "%h %h %h %h %h %h %h %h %h %h %h %h\n", ctl, acc, bias, lo, hi, m, sh, h, sv, rmode, omode, t)
               == 12) begin
            {rst_n, vld, relu, sgn} = ctl;
            #5 clk = 1;
            #1;
            if ($fscanf(fe, "%d %h %h %h\n", d, ev, ey, eb) != 4) $fatal(1, "exp file short at cycle %0d", n);
            if (d != 0) begin
                nchk++;
                if (vld_o !== ev || y_o !== ey || b_o !== eb) begin
                    nerr++;
                    if (nerr <= 10) $display("MISMATCH cycle %0d vld %b y %h b %b exp %b %h %b", n, vld_o, y_o, b_o,
                                             ev, ey, eb);
                end
            end
            #4 clk = 0;
            n++;
        end
        $display("QB_TB %s MW=%0d cycles %0d checked %0d errors %0d %s", `"`QBF_DUT`", MW, n, nchk, nerr,
                 (nerr == 0 && nchk > 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
