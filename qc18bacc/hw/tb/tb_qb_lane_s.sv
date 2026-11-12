// Self-check bench of the qb_lane_s variants (Verilator --binary).  Defines: TOP (DUT module), XW, MW, TW, SW (port
// widths).  Reads +stim=<file> (per cycle: ctl x m sh h r t, hex; ctl = {rst_n, vld, mode, ld}) and +exp=<file> (per
// cycle after the clock edge: <defined 0/1> <vld_o> <y_o hex> <b_o>), written by gen_s.py; prints QB_TB PASS / FAIL.
module tb_qb_lane_s;
    localparam int XW = `XW, MW = `MW, TW = `TW, SW = `SW;
    logic clk = 0, rst_n, vld, mode, ld, vld_o, b_o, ev, eb;
    logic signed [XW-1:0] x;
    logic        [MW-1:0] m;
    logic        [SW-1:0] sh;
    logic signed [15:0]   h, r, y_o, ey;
    logic signed [TW-1:0] t;
    logic [3:0] ctl;
    int fs, fe, n, nchk, nerr, d;
    string sf, ef;

    `TOP dut (.*);

    initial begin
        if (!$value$plusargs("stim=%s", sf) || !$value$plusargs("exp=%s", ef)) $fatal(1, "need +stim= +exp=");
        fs = $fopen(sf, "r"); fe = $fopen(ef, "r");
        if (fs == 0 || fe == 0) $fatal(1, "cannot open stim / exp");
        n = 0; nchk = 0; nerr = 0;
        while ($fscanf(fs, "%h %h %h %h %h %h %h\n", ctl, x, m, sh, h, r, t) == 7) begin
            {rst_n, vld, mode, ld} = ctl;
            ld = 1'b1;
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
        $display("QB_TB %s XW=%0d MW=%0d TW=%0d SW=%0d cycles %0d checked %0d errors %0d %s", `"`TOP`", XW, MW, TW, SW,
                 n, nchk, nerr, (nerr == 0 && nchk > 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
