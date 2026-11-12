// Self-check bench of qb_pe (Verilator --binary).  Reads +stim=<file> (per cycle: a c ctl sh_in, hex; ctl = {rst_n,
// plane[2:0], neg, valid, first, capture, shift}) and +exp=<file> (per cycle after the clock edge: <defined 0/1>
// <sh_out hex>), both written by gen.py; compares sh_out after every edge; prints QB_TB PASS / FAIL.
module tb_qb_pe;
    parameter int KB    = 16;
    parameter int ACC_W = 20;
    logic clk = 0, rst_n;
    logic [KB*8-1:0]  a;
    logic [KB*10-1:0] c;
    logic [2:0]       plane;
    logic             neg, valid, first, capture, shift;
    logic [ACC_W-1:0] sh_in, sh_out, e;
    logic [8:0]       ctl;
    int fs, fe, n, nchk, nerr, d;
    string sf, ef;

    qb_pe #(.KB(KB), .ACC_W(ACC_W)) dut (.*);

    initial begin
        if (!$value$plusargs("stim=%s", sf) || !$value$plusargs("exp=%s", ef)) $fatal(1, "need +stim= +exp=");
        fs = $fopen(sf, "r"); fe = $fopen(ef, "r");
        if (fs == 0 || fe == 0) $fatal(1, "cannot open stim / exp");
        n = 0; nchk = 0; nerr = 0;
        while ($fscanf(fs, "%h %h %h %h\n", a, c, ctl, sh_in) == 4) begin
            {rst_n, plane, neg, valid, first, capture, shift} = ctl;
            #5 clk = 1;
            #1;
            if ($fscanf(fe, "%d %h\n", d, e) != 2) $fatal(1, "exp file short at cycle %0d", n);
            if (d != 0) begin
                nchk++;
                if (sh_out !== e) begin
                    nerr++;
                    if (nerr <= 10) $display("MISMATCH cycle %0d sh_out %h exp %h", n, sh_out, e);
                end
            end
            #4 clk = 0;
            n++;
        end
        $display("QB_TB qb_pe KB=%0d ACC_W=%0d cycles %0d checked %0d errors %0d %s", KB, ACC_W, n, nchk, nerr,
                 (nerr == 0 && nchk > 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
