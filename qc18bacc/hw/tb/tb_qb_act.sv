// Pass-level bench of qb_act against export_act.py vectors (Verilator --binary).  +dir=<image dir>.
// Per array pass: the map macros (2 maps x 4 behavioural rf_2p 128 x 128, 1-cycle read, Q muxed by the registered
// map bit) are loaded with mem_<pi>.txt (= the dataflow source buffer before the pass, compile/layout.py), qb_act
// runs the pass, and every act-port item (descriptor fields + 4608-b act) and every end-of-tile marker is compared in
// order with exp_<pi>.txt.  Prints one QB_ACT line per pass and a QB_ACT_TB PASS / FAIL summary.
module tb_rf2p (input logic clk, input logic ren, input logic [6:0] ra, input logic [127:0] mem [128],
                output logic [127:0] q);
    always_ff @(posedge clk) if (ren) q <= mem[ra];     // rf_2p read port: 1-cycle latency, Q holds
endmodule

module tb_qb_act;
    localparam int AP = 1;
    logic clk = 0, rst_n = 0;
    logic start = 0, c_int8 = 0, c_stem = 0;
    logic [3:0] c_cfg = 0, c_nct = 0;
    logic [4:0] c_nchunk = 0;
    logic [6:0] c_ntile = 0;
    logic [8:0] c_base = 0;
    logic busy, done, m_ren;
    logic [8:0] m_ra;
    logic [511:0] m_q;
    logic d_vld, d_first, d_eot, d_neg, d_stem, d_g3n, a_vld, a_first, a_eot, a_neg, a_stem, a_g3n;
    logic [2:0] d_plane, a_plane, d_ct, a_ct;
    logic [3:0] d_chunk, a_chunk;
    logic [5:0] d_tile, a_tile;
    logic [4607:0] act;

    qb_act #(.ACT_PIPE(AP)) dut (.*);

    logic [127:0] qa [4], qb [4];
    logic [127:0] ma [4][128], mb [4][128];
    logic msel;
    for (genvar m = 0; m < 4; m++) begin : g_mac
        tb_rf2p ua (.clk, .ren(m_ren && !m_ra[7]), .ra(m_ra[6:0]), .mem(ma[m]), .q(qa[m]));
        tb_rf2p ub (.clk, .ren(m_ren &&  m_ra[7]), .ra(m_ra[6:0]), .mem(mb[m]), .q(qb[m]));
    end
    always_ff @(posedge clk) if (m_ren) msel <= m_ra[7];
    always_comb for (int m = 0; m < 4; m++) m_q[128 * m +: 128] = msel ? qb[m] : qa[m];

    logic [511:0] lines [256];
    string dir, nm, tag, fn;
    int fp, fe, pi, cfg, nch, nct, ntl, i8, stm, nln, nit, rc, cyc, ncmp, nerr, nbit, nev, tot_cmp, tot_err, tot_cyc;
    int xf, xpl, xng, xst, xg3, xch, xct, xtl;
    logic [4607:0] xact;
    bit dbg;

    task automatic tick();
        #5 clk = 1; #5 clk = 0;
    endtask

    initial begin
        dbg = $test$plusargs("dbg");
        if (!$value$plusargs("dir=%s", dir)) $fatal(1, "need +dir=");
        fp = $fopen({dir, "/passes_act.txt"}, "r");
        if (fp == 0) $fatal(1, "no passes_act.txt in %s", dir);
        tot_cmp = 0; tot_err = 0; tot_cyc = 0;
        tick(); tick(); rst_n = 1; tick();
        while ($fscanf(fp, "%d %s %d %d %d %d %d %d %d %d\n", pi, nm, cfg, nch, nct, ntl, i8, stm, nln, nit) == 10) begin
            for (int a = 0; a < 256; a++) lines[a] = '0;
            $readmemh($sformatf("%s/mem_%0d.txt", dir, pi), lines, 0, nln - 1);
            for (int a = 0; a < 128; a++)
                for (int m = 0; m < 4; m++) begin
                    ma[m][a] = lines[a][128 * m +: 128];
                    mb[m][a] = lines[128 + a][128 * m +: 128];
                end
            fe = $fopen($sformatf("%s/exp_%0d.txt", dir, pi), "r");
            c_cfg = 4'(cfg); c_nchunk = 5'(nch); c_nct = 4'(nct); c_ntile = 7'(ntl); c_int8 = i8[0]; c_stem = stm[0];
            c_base = '0;
            start = 1; tick(); start = 0;
            cyc = 1; ncmp = 0; nerr = 0; nbit = 0; nev = 0;
            while (!done && cyc < 200000) begin
                #1;
                if (dbg && pi == 0 && cyc < 30) $display("DBG cyc %0d vld %b eot %b f %b pl %0d ch %0d t %0d st %0d", cyc, a_vld, a_eot, a_first, a_plane, a_chunk, a_tile, dut.st);
                if (a_vld === 1'b1) begin
                    rc = $fscanf(fe, "%s", tag);
                    if (rc != 1 || tag != "I") begin
                        nerr++; if (nerr <= 3) $display("MISMATCH pass %0d cycle %0d: unexpected item (exp %s)", pi, cyc, tag);
                    end else begin
                        rc = $fscanf(fe, "%d %d %d %d %d %d %d %d %h\n", xf, xpl, xng, xst, xg3, xch, xct, xtl, xact);
                        ncmp++;
                        if ({a_first, a_plane, a_neg, a_stem, a_g3n, a_chunk, a_ct, a_tile} !==
                            {xf[0], 3'(xpl), xng[0], xst[0], xg3[0], 4'(xch), 3'(xct), 6'(xtl)} || act !== xact) begin
                            nerr++;
                            nbit += $countones(act ^ xact);
                            if (nerr <= 3)
                                $display("MISMATCH pass %0d item %0d: f %0d pl %0d ng %0d st %0d g3 %0d ch %0d ct %0d t %0d (exp %0d %0d %0d %0d %0d %0d %0d %0d) act bits %0d",
                                         pi, ncmp, a_first, a_plane, a_neg, a_stem, a_g3n, a_chunk, a_ct, a_tile,
                                         xf, xpl, xng, xst, xg3, xch, xct, xtl, $countones(act ^ xact));
                        end
                    end
                end
                if (a_eot === 1'b1) begin
                    rc = $fscanf(fe, "%s", tag);
                    if (rc != 1 || tag != "E") begin
                        nerr++; if (nerr <= 3) $display("MISMATCH pass %0d cycle %0d: unexpected end of tile (exp %s)", pi, cyc, tag);
                    end else begin
                        rc = $fscanf(fe, "%d %d\n", xct, xtl);
                        nev++;
                        if (a_ct !== 3'(xct) || a_tile !== 6'(xtl)) begin
                            nerr++; if (nerr <= 3) $display("MISMATCH pass %0d eot ct %0d tile %0d exp %0d %0d", pi, a_ct, a_tile, xct, xtl);
                        end
                    end
                end
                #4 clk = 1; #5 clk = 0;
                cyc++;
            end
            if ($fscanf(fe, "%s", tag) == 1) begin nerr++; $display("MISMATCH pass %0d: missing items (next %s)", pi, tag); end
            if (ncmp != nit) begin nerr++; $display("MISMATCH pass %0d: %0d items, expected %0d", pi, ncmp, nit); end
            $fclose(fe);
            $display("QB_ACT pass %0d %s cfg %0d items %0d eot %0d cycles %0d err %0d bits %0d", pi, nm, cfg, ncmp, nev,
                     cyc, nerr, nbit);
            tot_cmp += ncmp; tot_err += nerr; tot_cyc += cyc;
            tick();
        end
        $display("QB_ACT_TB %s items %0d act_bytes %0d cycles %0d errors %0d %s", dir, tot_cmp, tot_cmp * 576, tot_cyc,
                 tot_err, (tot_err == 0 && tot_cmp > 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
