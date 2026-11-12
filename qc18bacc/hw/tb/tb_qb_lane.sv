// Self-check bench of qb_lane_n / qb_lane_w (Verilator --binary, -DLANE_W selects qb_lane_w).  Reads +stim=<file>
// (per cycle: ctl x m sh h r t, hex, two's complement; ctl = {rst_n, vld, mode}) and +exp=<file> (per cycle after
// the clock edge: <defined 0/1> <vld_o> <y_o hex> <b_o>), written by gen.py; prints QB_TB PASS / FAIL.
module tb_qb_lane;
`ifdef LANE_W
    localparam int XW = 20, MW = 31, TW = 21;
`else
    localparam int XW = 16, MW = 27, TW = 17;
`endif
    logic clk = 0, rst_n, vld, mode, vld_o, b_o, ev, eb;
    logic signed [XW-1:0] x;
    logic        [MW-1:0] m;
    logic        [5:0]    sh;
    logic signed [15:0]   h, r, y_o, ey;
    logic signed [TW-1:0] t;
    logic [2:0] ctl;
    int fs, fe, n, nchk, nerr, d;
    string sf, ef;

`ifdef LANE_W
    qb_lane_w dut (.*);
`else
    qb_lane_n dut (.*);
`endif

    initial begin
        if (!$value$plusargs("stim=%s", sf) || !$value$plusargs("exp=%s", ef)) $fatal(1, "need +stim= +exp=");
        fs = $fopen(sf, "r"); fe = $fopen(ef, "r");
        if (fs == 0 || fe == 0) $fatal(1, "cannot open stim / exp");
        n = 0; nchk = 0; nerr = 0;
        while ($fscanf(fs, "%h %h %h %h %h %h %h\n", ctl, x, m, sh, h, r, t) == 7) begin
            {rst_n, vld, mode} = ctl;
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
        $display("QB_TB qb_lane XW=%0d MW=%0d cycles %0d checked %0d errors %0d %s", XW, MW, n, nchk, nerr,
                 (nerr == 0 && nchk > 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
