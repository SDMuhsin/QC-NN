// Full-image bench of qb_top (R3a) against export_top.py vectors (Verilator --binary).  +dir=<image dir>.
// Host load (weights, parameter sets, image, descriptor memories) through the host port, go, run to the model's end.
// Checks, every pass of the image (stem .. b7.c2):
//   * core outputs in pass order vs export_core (core/exp_b2 / exp_f / exp_w): b2, fused s_out / r / u8 (hq) + b1_next,
//     wide u8 (z) / r / s + b1, attributed to passes by the top's own tags;
//   * every act-port item + end-of-tile marker in pass order vs export_act (act/exp_<pi>): this is what the array
//     read back from the written maps (B1 / B2) and S words (HQ / HQD / Z), so it checks the write-back layout;
//   * every tile end (last issue + 1) vs the model (sched.txt X, cycle-exact);
//   * S after the image: block 7's output stream vs s_final.txt (physical layout);
//   * err (port conflicts, R/W same address, latency / tag mismatches, FIFO overflow) never set.
// R3b hook (+define+QBT_R3B): qb_top R3B = 1 (image-independent sequencer + params bank); the network program
// (weights, params bank rows, pass table, context pass lists, load-permission entries, descriptors, fetch lists) is
// read from +prog=<dir> (export_top2.py, one per seed), the image and the expected values from +dir=<image dir>.
// Cycles: RTL image end = cycle after the last macro write; reported against the model (sched.txt M: with / without
// the write-back latency hook).
module tb_qb_top;
`ifndef QBT_DIST
`define QBT_DIST 1
`endif
    localparam int DIST = `QBT_DIST, AP = 1, NP = 32, MAXC = 8000;
    logic clk = 0, rst_n = 0, go = 0, h_we = 0;
    logic [3:0] h_sel = 0;
    logic [9:0] h_addr = 0;
    logic [5188:0] h_data = 0;
    logic [15:0] now;
    logic err;
    logic wb_fv, dbg_wv, dbg_bv, dbg_av, ae_ctx, ae_eot, dbg_af, dbg_aneg, dbg_astem, dbg_ag3n;
    logic [4:0] wb_fpi, dbg_wpi, dbg_bpi, ae_pic0, ae_pic1;
    logic [6:0] dbg_ftp;
    logic [3:0] wb_fct;
    logic [1:0] wb_fk;
    int hm_pi, hm_l0;
    logic [4351:0] wb_fy;
    logic [255:0] dbg_fb;
    logic [607:0] dbg_wy;
    logic [31:0] dbg_wb;
    logic [1023:0] dbg_b2;
    logic [2:0] dbg_apl, dbg_act_ct;
    logic [3:0] dbg_ach;
    logic [5:0] dbg_atile;
    logic [4607:0] dbg_act;
    logic [7:0] dbg_sa = 0;
    logic [4095:0] dbg_sq;

`ifdef QBT_R3B
    qb_top #(.DIST(DIST), .AP(AP), .R3B(1)) dut (.*);
`else
    qb_top #(.DIST(DIST), .AP(AP)) dut (.*);
`endif

    string dir, pdir, tag, nm;
    int fp, rc, a, b, c, d, n, k, cyc;
    logic [5188:0] w;
    // expected core outputs, per pass in order
    logic [4351:0] xfy [1600];  logic [255:0] xfb [1600];  int xfpi [1600];  int nxf;
    logic [607:0]  xwy [1024];  logic [31:0]  xwb [1024];  int xwpi [1024];  int nxw;
    logic [1023:0] xb2 [1024];  int xbpi [1024];  int nxb;
    int fptr [NP], wptr [NP], bptr [NP], ef [NP], ew [NP], eb [NP], cf [NP], cw [NP], cb [NP];
    int fe [NP], ni [NP], ei [NP], ne [NP];
    int X_pi [1024], X_tp [1024], X_ct [1024], X_ce [1024], nX, ce_rtl [NP][64][8], cyc_err, M, M0;
    int tot_err, tot_chk, last_wr, nfin, efin, xf, xpl, xng, xst, xg3, xch, xct, xtl;
    logic [4607:0] xact;
    logic [127:0] sv;

    task automatic tick(); #5 clk = 1; #5 clk = 0; endtask
    task automatic hw(int sel, int addr, logic [5188:0] data);
        h_we = 1; h_sel = 4'(sel); h_addr = 10'(addr); h_data = data; tick(); h_we = 0;
    endtask
    task automatic load_q(string f, int sel, int cid);
        int cnt;
        fp = $fopen({pdir, "/", f}, "r");
        if (fp == 0) $fatal(1, "cannot open %s", f);
        rc = $fscanf(fp, "%d\n", cnt);
        for (int i = 0; i < cnt; i++) begin rc = $fscanf(fp, "%h\n", w); hw(sel, i, w); end
        $fclose(fp);
        if (cid >= 0) hw(15, cid, 5189'(cnt));
    endtask
    function automatic int nextidx(ref int pi_of [1600], input int from, input int pi, input int n_);
        for (int i = from; i < n_; i++) if (pi_of[i] == pi) return i;
        return n_;
    endfunction

    initial begin
        if (!$value$plusargs("dir=%s", dir)) $fatal(1, "need +dir=");
`ifdef QBT_R3B
        if (!$value$plusargs("prog=%s", pdir)) $fatal(1, "need +prog=");
`else
        pdir = dir;
`endif
        tick(); tick(); rst_n = 1; tick();
        // ---- host load
        fp = $fopen({pdir, "/w_rows.txt"}, "r"); n = 0;
        while ($fscanf(fp, "%h\n", w) == 1) begin hw(0, n, w); n++; end
        $fclose(fp);
`ifdef QBT_R3B
        fp = $fopen({pdir, "/p_rows.txt"}, "r"); n = 0;
`else
        fp = $fopen({dir, "/p_sets.txt"}, "r"); n = 0;
`endif
        while ($fscanf(fp, "%h\n", w) == 1) begin hw(1, n, w); n++; end
        $fclose(fp);
        fp = $fopen({dir, "/img.txt"}, "r"); n = 0;
        while ($fscanf(fp, "%h\n", w) == 1) begin hw(2, n, w); n++; end
        $fclose(fp);
`ifdef QBT_R3B
        load_q("d_pt.txt", 3, -1); load_q("d_p0.txt", 4, 0); load_q("d_p1.txt", 5, 1); load_q("d_lt.txt", 10, -1);
        load_q("d_ds.txt", 11, 7); hw(15, 6, 0);
        load_q("d_ff.txt", 12, 8); load_q("d_fw.txt", 13, 9); load_q("d_ft.txt", 14, 10);
`else
        load_q("d_pt.txt", 3, -1); load_q("d_p0.txt", 4, 0); load_q("d_p1.txt", 5, 1); load_q("d_tq.txt", 6, 2);
        load_q("d_cq.txt", 7, 3); load_q("d_fq.txt", 8, 4); load_q("d_wq.txt", 9, 5); load_q("d_lt.txt", 10, -1);
`endif
        // ---- expected
        nxf = 0; fp = $fopen({dir, "/core/exp_f.txt"}, "r");
        while ($fscanf(fp, "%d %h %h\n", xfpi[nxf], xfy[nxf], xfb[nxf]) == 3) nxf++;
        $fclose(fp);
        nxw = 0; fp = $fopen({dir, "/core/exp_w.txt"}, "r");
        while ($fscanf(fp, "%d %h %h\n", xwpi[nxw], xwy[nxw], xwb[nxw]) == 3) nxw++;
        $fclose(fp);
        nxb = 0; fp = $fopen({dir, "/core/exp_b2.txt"}, "r");
        while ($fscanf(fp, "%d %h\n", xbpi[nxb], xb2[nxb]) == 2) nxb++;
        $fclose(fp);
        hm_pi = -1; hm_l0 = 0;
        fp = $fopen({dir, "/core/passes.txt"}, "r");
        while ($fscanf(fp, "%d %s\n", a, nm) == 2) if (nm == "b6.hm") hm_pi = a;
        $fclose(fp);
        for (int i = 0; i < nxf; i++) if (xfpi[i] == hm_pi) begin hm_l0 = i; break; end
        nX = 0; fp = $fopen({dir, "/sched.txt"}, "r");
        while ($fscanf(fp, "%s", tag) == 1) begin
            if (tag == "X") begin rc = $fscanf(fp, "%d %d %d %d\n", X_pi[nX], X_tp[nX], X_ct[nX], X_ce[nX]); nX++; end
            else rc = $fscanf(fp, "%d %d\n", M, M0);
        end
        $fclose(fp);
        for (int p = 0; p < NP; p++) begin
            fptr[p] = -1; wptr[p] = -1; bptr[p] = -1; ef[p] = 0; ew[p] = 0; eb[p] = 0; cf[p] = 0; cw[p] = 0; cb[p] = 0;
            ni[p] = 0; ei[p] = 0; ne[p] = 0;
            fe[p] = $fopen($sformatf("%s/act/exp_%0d.txt", dir, p), "r");
            for (int t = 0; t < 64; t++) for (int u = 0; u < 8; u++) ce_rtl[p][t][u] = -1;
        end
        tot_err = 0; tot_chk = 0; cyc_err = 0; last_wr = -1;
        // ---- run
        go = 1; tick(); go = 0;
        for (cyc = 0; cyc < M + 200; cyc++) begin
            #1;
            if (int'(now) != cyc) $fatal(1, "time base %0d != %0d", now, cyc);
            if (wb_fv === 1'b1) begin
                int p, i;
                p = wb_fpi;
                i = nextidx(xfpi, fptr[p] + 1, p, nxf);
                fptr[p] = i;
                if (p == hm_pi) begin
                    // hm job of qb_top = 4 px x 64 ch (tile (tp, cg), step k); export_core's = 1 px x 256 ch per line
                    cf[p] += 256;
                    for (int q = 0; q < 4; q++)
                        for (int ch = 0; ch < 64; ch++) begin
                            int px, l, ln;
                            px = 16 * dbg_ftp + 4 * wb_fk + q;
                            l  = 64 * q + ch;
                            ln = hm_l0 + px;
                            if (wb_fy[17 * l +: 17] !== xfy[ln][17 * (64 * wb_fct + ch) +: 17] || dbg_fb[l] !== 1'b0) begin
                                ef[p]++;
                                if (ef[p] <= 3) $display("MISMATCH hm cycle %0d px %0d ch %0d: y %h exp %h", cyc, px,
                                                         64 * wb_fct + ch, wb_fy[17 * l +: 17], xfy[ln][17 * (64 * wb_fct + ch) +: 17]);
                            end
                        end
                end else if (i >= nxf) begin ef[p]++; $display("MISMATCH extra fused word pass %0d cycle %0d", p, cyc); end
                else begin
                    cf[p] += 256;
                    for (int l = 0; l < 256; l++)
                        if (wb_fy[17 * l +: 17] !== xfy[i][17 * l +: 17] || dbg_fb[l] !== xfb[i][l]) begin
                            ef[p]++;
                            if (ef[p] <= 3) $display("MISMATCH fused pass %0d cycle %0d lane %0d: y %h b %b exp %h %b", p, cyc, l,
                                                     wb_fy[17 * l +: 17], dbg_fb[l], xfy[i][17 * l +: 17], xfb[i][l]);
                        end
                end
            end
            if (dbg_wv === 1'b1) begin
                int p, i;
                p = dbg_wpi;
                i = wptr[p] + 1;
                while (i < nxw && xwpi[i] != p) i++;
                wptr[p] = i;
                if (i >= nxw) begin ew[p]++; $display("MISMATCH extra wide word pass %0d cycle %0d", p, cyc); end
                else begin
                    cw[p] += 32;
                    for (int l = 0; l < 32; l++)
                        if (dbg_wy[19 * l +: 19] !== xwy[i][19 * l +: 19] || dbg_wb[l] !== xwb[i][l]) begin
                            ew[p]++;
                            if (ew[p] <= 3) $display("MISMATCH wide pass %0d cycle %0d lane %0d: y %h b %b exp %h %b", p, cyc, l,
                                                     dbg_wy[19 * l +: 19], dbg_wb[l], xwy[i][19 * l +: 19], xwb[i][l]);
                        end
                end
            end
            if (dbg_bv === 1'b1) begin
                int p, i, e;
                p = dbg_bpi;
                i = bptr[p] + 1;
                while (i < nxb && xbpi[i] != p) i++;
                bptr[p] = i;
                if (i >= nxb) begin eb[p]++; $display("MISMATCH extra b2 word pass %0d cycle %0d", p, cyc); end
                else begin
                    cb[p] += 1024;
                    e = $countones(dbg_b2 ^ xb2[i]);
                    if ($isunknown(dbg_b2)) e = 1024;
                    if (e != 0 && eb[p] == 0) $display("MISMATCH b2 pass %0d cycle %0d: %0d bits", p, cyc, e);
                    eb[p] += e;
                end
            end
            if (dbg_av === 1'b1 || ae_eot === 1'b1) begin
                int p;
                p = ae_ctx ? ae_pic1 : ae_pic0;
                if (dbg_av === 1'b1) begin
                    rc = $fscanf(fe[p], "%s", tag);
                    if (rc != 1 || tag != "I") begin ei[p]++; if (ei[p] <= 3) $display("MISMATCH pass %0d cycle %0d: unexpected item", p, cyc); end
                    else begin
                        rc = $fscanf(fe[p], "%d %d %d %d %d %d %d %d %h\n", xf, xpl, xng, xst, xg3, xch, xct, xtl, xact);
                        ni[p]++;
                        if ({dbg_af, dbg_apl, dbg_aneg, dbg_astem, dbg_ag3n, dbg_ach, dbg_act_ct, dbg_atile} !==
                            {xf[0], 3'(xpl), xng[0], xst[0], xg3[0], 4'(xch), 3'(xct), 6'(xtl)} || dbg_act !== xact) begin
                            ei[p]++;
                            if (ei[p] <= 3) $display("MISMATCH act pass %0d item %0d cycle %0d: ch %0d ct %0d t %0d pl %0d (exp %0d %0d %0d %0d) act bits %0d",
                                                     p, ni[p], cyc, dbg_ach, dbg_act_ct, dbg_atile, dbg_apl, xch, xct, xtl, xpl,
                                                     $countones(dbg_act ^ xact));
                        end
                    end
                end
                if (ae_eot === 1'b1) begin
                    rc = $fscanf(fe[p], "%s", tag);
                    if (rc != 1 || tag != "E") begin ei[p]++; if (ei[p] <= 3) $display("MISMATCH pass %0d cycle %0d: unexpected eot", p, cyc); end
                    else begin
                        rc = $fscanf(fe[p], "%d %d\n", xct, xtl);
                        ne[p]++;
                        if (dbg_act_ct !== 3'(xct) || dbg_atile !== 6'(xtl)) ei[p]++;
                    end
                    ce_rtl[p][dbg_atile][dbg_act_ct] = cyc - 2 - AP;
                end
            end
            if ((|dut.s_we) || (|dut.b_we[0]) || (|dut.b_we[1])) last_wr = cyc;
            #4 clk = 1; #5 clk = 0;
        end
        // ---- after the image
        for (int i = 0; i < nX; i++)
            if (ce_rtl[X_pi[i]][X_tp[i]][X_ct[i]] != X_ce[i]) begin
                cyc_err++;
                if (cyc_err <= 5) $display("CYCLE_MISMATCH pass %0d tile %0d ct %0d: rtl ce %0d model ce %0d", X_pi[i], X_tp[i],
                                           X_ct[i], ce_rtl[X_pi[i]][X_tp[i]][X_ct[i]], X_ce[i]);
            end
        nfin = 0; efin = 0;
        fp = $fopen({dir, "/s_final.txt"}, "r");
        while ($fscanf(fp, "%d %d %h\n", a, b, sv) == 3) begin
            nfin++;
            dbg_sa = 8'(a); #1;
            if (dbg_sq[128 * b +: 128] !== sv) begin
                efin++;
                if (efin <= 3) $display("MISMATCH final S addr %0d lane %0d: %h exp %h", a, b, dbg_sq[128 * b +: 128], sv);
            end
        end
        $fclose(fp);
        for (int p = 0; p < NP; p++) begin
            int lf;
            if (fe[p] == 0) lf = 0;
            else begin lf = ($fscanf(fe[p], "%s", tag) == 1); $fclose(fe[p]); end
            if (lf) begin ei[p]++; $display("MISMATCH pass %0d: act items missing", p); end
            if (cf[p] + cw[p] + cb[p] + ni[p] > 0) begin
                $display("QB_TOP pass %0d items %0d eot %0d act_err %0d b2_bits %0d err %0d fused_words %0d err %0d wide_words %0d err %0d",
                         p, ni[p], ne[p], ei[p], cb[p], eb[p], cf[p], ef[p], cw[p], ew[p]);
                tot_err += ei[p] + eb[p] + ef[p] + ew[p];
                tot_chk += ni[p] + cb[p] + cf[p] + cw[p];
            end
        end
        for (int p = 0; p < NP; p++) begin
            int xn_f, xn_w, xn_b;
            xn_f = 0; xn_w = 0; xn_b = 0;
            for (int i = 0; i < nxf; i++) xn_f += (xfpi[i] == p);
            for (int i = 0; i < nxw; i++) xn_w += (xwpi[i] == p);
            for (int i = 0; i < nxb; i++) xn_b += (xbpi[i] == p);
            if (cf[p] != 256 * xn_f || cw[p] != 32 * xn_w || cb[p] != 1024 * xn_b) begin
                tot_err++; $display("MISMATCH pass %0d: output words %0d / %0d / %0d, expected %0d / %0d / %0d", p,
                                    cf[p] / 256, cw[p] / 32, cb[p] / 1024, xn_f, xn_w, xn_b);
            end
        end
        tot_err += efin + (err ? 1 : 0);
        if (err) $display("MISMATCH qb_top err flag set");
        $display("QB_TOP_CYC rtl_end %0d (last macro write %0d + 1) model %0d (config C without lat %0d) delta_vs_model %0d delta_vs_configC %0d",
                 last_wr + 1, last_wr, M, M0, last_wr + 1 - M, last_wr + 1 - M0);
        $display("QB_TOP_TB %s checked %0d final_S_words %0d err %0d tiles %0d cycle_mismatch %0d errors %0d %s", dir, tot_chk,
                 nfin, efin, nX, cyc_err, tot_err, (tot_err == 0 && cyc_err == 0 && tot_chk > 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
