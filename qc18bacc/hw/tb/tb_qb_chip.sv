// Image-to-logits streaming bench of qb_chip (R3c; Verilator --binary), vectors of hw/tb/export_top3.py.
//   +prog=<prog dir> +n=<images> +dir0=<img dir> +dir1=... : one program load, then the images back to back.
// Host model: loads the program, FC rows, head config and image 0, gives h_go; loads image i + 1 into IMG as soon as
// st_img_free rises during image i (one 512-b line per cycle), gives h_go for image i + 1 in the first cycle st_idle is
// seen.  Checks:
//   * logits (int32, all classes) vs logits.txt (IntBin2 integer logits); writes <dir>/logits_rtl<+tag>.txt for the
//     torch.equal check (export_top3.py --check);
//   * every array tile end of every image cycle-exact vs that image's static-order model (sched.txt X);
//   * no IMG read while the host may write IMG; err never set.
// Reports per image: go cycle, interval to the next go, image cycles (RTL end, model M), head latency.
// R6a (+define+QB_HPW=W, qb_chip narrow host port): every wide word is written as macro words (weights 16 x 144 b,
// params 9 x 144, IMG line 4 x 128, h_lane = index; other selects one write), the next image one 128-b word per
// cycle; h_go of image 0 waits the port latency (10 cycles).  Reports the program / image load cycles (QB_CHIP_HPW).
module tb_qb_chip;
    localparam int AP = 1, NP = 32, MAXI = 8;
    logic clk = 0, rst_n = 0, h_we = 0, h_go = 0;
    logic [4:0] h_sel = 0;
    logic [10:0] h_addr = 0;
`ifdef QB_HPW
    localparam int HPW = `QB_HPW;
    logic [HPW-1:0] h_data = 0;
    logic [4:0] h_lane = 0;
    int nwr = 0, nwr_w = 0, ld_lane = 0, ldone_c [MAXI];
`else
    logic [5188:0] h_data = 0;
`endif
    logic st_idle, st_img_free, st_head_busy, lo_vld, err;
    logic [6:0] lo_idx;
    logic [31:0] lo_val;
    logic [15:0] now;
    qb_chip dut (.*);
`ifdef QBT_VSAIF
    // R4 gate-level power hook (VCS, +define+QBT_GLS+QBT_VSAIF): toggle counts of the whole DUT over the steady-state
    // interval [go of image 1, go of image 2) -> SAIF +vsaif=<file> (impl/r4/gls.sh).
    string vsaif_fn;
    int vsaif_c0;
    initial if (!$value$plusargs("vsaif=%s", vsaif_fn)) vsaif_fn = "qb_chip_gls.saif";
`endif
`ifdef QBT_SAIF
    // R4 power hook: SAIF of the whole run from time 0 (Verilator --trace-saif), stopped ($finish) at the go of image
    // +saif_stop=<k>; the steady-state window [go k-1, go k) = difference of two runs (impl/r4/saif_window.py).
    int saif_stop;
    initial begin
        if (!$value$plusargs("saif_stop=%d", saif_stop)) saif_stop = -1;
        if ($test$plusargs("saif")) begin $dumpfile("qb_chip.saif"); $dumpvars(0, dut); end
    end
`endif

    string pdir, dir [MAXI], tag, otag;
    int fp, rc, n, N, cnt, cyc;
    logic [5188:0] w;
    logic [511:0] img [MAXI][128];
    int xlg [MAXI][100], rlg [MAXI][100], nlg [MAXI], lg_last [MAXI], ncls;
    int go_c [MAXI], end_c [MAXI], end_now [MAXI], M [MAXI], M0 [MAXI];
    int X_pi [MAXI][1024], X_tp [MAXI][1024], X_ct [MAXI][1024], X_ce [MAXI][1024], nX [MAXI];
    int ce_rtl [NP][64][8], cyc_err [MAXI], lg_err [MAXI], img_rd_err, cur, ld_img, ld_line, lo_img, timeout;
    int free_c [MAXI], pq0_c [MAXI], fcd_c [MAXI], nfcd;
`ifdef QBT_WBSTAT
    // R7d measurement hook (default off): per-cycle S write-request classes of the QB_TOP_WBR write-back (0 HQ, 1 HQD,
    // 2 Z, 3 stream, 4 r, 5 b6.c2; 6 = S-read rotator in use = s_ren one cycle earlier), co-occurrence matrix, shift
    // histograms of the HQ (l0) / HQD (bq) / Z (bz) rotators and of the S-read rotator (s_rot), wr_conf cycles.
    longint ws_co [7][7], ws_h [4][16], ws_cyc, ws_conf, ws_last [7], ws_md [7][7];   // md: min cycle distance i -> j
    logic ws_sren_d = 1'b0;  logic [3:0] ws_srot_d = '0;
    initial begin
        ws_cyc = 0; ws_conf = 0;
        for (int i = 0; i < 7; i++) begin ws_last[i] = -1000000; for (int j = 0; j < 7; j++) ws_md[i][j] = 1000000; end
        for (int i = 0; i < 7; i++) for (int j = 0; j < 7; j++) ws_co[i][j] = 0;
        for (int i = 0; i < 4; i++) for (int j = 0; j < 16; j++) ws_h[i][j] = 0;
    end
    task automatic ws_sample();
        logic [6:0] a;  logic f, w;  logic [3:0] y, l0, bq, bz;
        f = dut.u_top.fo.v && dut.u_top.f_vld_o;
        w = dut.u_top.wo.v && dut.u_top.w_vld_o;
        y  = 4'(2 * dut.u_top.fo.tp + 7'(dut.u_top.fo.k[1]));
        l0 = 4'(2 * y + 4'(dut.u_top.fo.k[0]));
        bq = {dut.u_top.fo.ct[0], 1'b0, 2'(y >> 1)};
        bz = {dut.u_top.wo.ct[0], 1'b0, 2'(dut.u_top.wo.k >> 3)};
        a = '0;
        a[0] = f && dut.u_top.fo.hm;
        a[1] = f && dut.u_top.fo.hm && !y[0];
        a[2] = w && dut.u_top.wo.kind == 3'd5;
        a[3] = f && !dut.u_top.fo.hm;
        a[4] = w && dut.u_top.wo.kind == 3'd6;
        a[5] = w && dut.u_top.wo.kind == 3'd7;
        a[6] = ws_sren_d;
        ws_cyc++;
        if (dut.u_top.wr_conf) ws_conf++;
        for (int i = 0; i < 7; i++) for (int j = 0; j < 7; j++) if (a[i] && a[j]) ws_co[i][j]++;
        for (int i = 0; i < 7; i++) if (a[i]) ws_last[i] = ws_cyc;
        for (int i = 0; i < 7; i++) if (a[i]) for (int j = 0; j < 7; j++)
            if (j != i && ws_cyc - ws_last[j] < ws_md[i][j]) begin ws_md[i][j] = ws_cyc - ws_last[j]; ws_md[j][i] = ws_md[i][j]; end
        if (a[0]) ws_h[0][l0]++;
        if (a[1]) ws_h[1][bq]++;
        if (a[2]) ws_h[2][bz]++;
        if (a[6]) ws_h[3][ws_srot_d]++;
        ws_sren_d = dut.u_top.s_ren;  ws_srot_d = dut.u_top.s_rot;
    endtask
`endif

    task automatic tick(); #5 clk = 1; #5 clk = 0; endtask
`ifndef QB_HPW
    task automatic hw(int sel, int addr, logic [5188:0] data);
        h_we = 1; h_sel = 5'(sel); h_addr = 11'(addr); h_data = data; tick(); h_we = 0;
    endtask
`else
    task automatic hw(int sel, int addr, logic [5188:0] data);
        int nl, lw;
        nl = sel == 0 ? 16 : sel == 1 ? 9 : sel == 2 ? 4 : 1;
        lw = sel == 2 ? 128 : sel <= 1 ? 144 : HPW;
        if ((data >> (nl * lw)) != 0) $fatal(1, "hw: sel %0d word wider than %0d x %0d b", sel, nl, lw);
        nwr_w++;
        for (int l = 0; l < nl; l++) begin
            h_we = 1; h_sel = 5'(sel); h_addr = 11'(addr); h_lane = 5'(l); h_data = HPW'((data >> (lw * l)) & ((5189'(1) << lw) - 1));
            tick(); nwr++;
        end
        h_we = 0; h_lane = 0;
    endtask
`endif
    task automatic load_f(string f, int sel, int cid, bit counted);
        int c;
        fp = $fopen({pdir, "/", f}, "r");
        if (fp == 0) $fatal(1, "cannot open %s", f);
        c = 0;
        if (counted) begin
            rc = $fscanf(fp, "%d\n", cnt);
            for (int i = 0; i < cnt; i++) begin rc = $fscanf(fp, "%h\n", w); hw(sel, i, w); end
            c = cnt;
        end else
            while ($fscanf(fp, "%h\n", w) == 1) begin
                if (sel == 16 && c >= 2048) hw(18, c - 2048, w);          // R5e (QB_HEAD_FW 128): FC rows 2048.. via h_sel 18
                else hw(sel, c, w);
                c++;
            end
        $fclose(fp);
        if (cid >= 0) hw(15, cid, 5189'(c));
    endtask

    initial begin
        if (!$value$plusargs("prog=%s", pdir)) $fatal(1, "need +prog=");
        if (!$value$plusargs("n=%d", N)) $fatal(1, "need +n=");
        if (!$value$plusargs("tag=%s", otag)) otag = "";                  // logits_rtl<tag>.txt (mutant builds)
        for (int i = 0; i < N; i++) begin
            if (!$value$plusargs($sformatf("dir%0d=%%s", i), dir[i])) $fatal(1, "need +dir%0d=", i);
            fp = $fopen({dir[i], "/img.txt"}, "r"); n = 0;
            while ($fscanf(fp, "%h\n", w) == 1) begin img[i][n] = w[511:0]; n++; end
            $fclose(fp);
            if (n != 128) $fatal(1, "img.txt of %s has %0d lines", dir[i], n);
            fp = $fopen({dir[i], "/logits.txt"}, "r"); ncls = 0;
            while ($fscanf(fp, "%d", xlg[i][ncls]) == 1) ncls++;
            $fclose(fp);
            nX[i] = 0; fp = $fopen({dir[i], "/sched.txt"}, "r");
            while ($fscanf(fp, "%s", tag) == 1) begin
                if (tag == "X") begin rc = $fscanf(fp, "%d %d %d %d\n", X_pi[i][nX[i]], X_tp[i][nX[i]], X_ct[i][nX[i]], X_ce[i][nX[i]]); nX[i]++; end
                else rc = $fscanf(fp, "%d %d\n", M[i], M0[i]);
            end
            $fclose(fp);
            nlg[i] = 0; lg_err[i] = 0; cyc_err[i] = 0; lg_last[i] = -1; pq0_c[i] = -1; fcd_c[i] = -1; end_c[i] = -1; go_c[i] = -1; free_c[i] = -1;
            for (int j = 0; j < 100; j++) rlg[i][j] = 'x;
        end
        tick(); tick(); rst_n = 1; tick();
        // ---- program load (once)
        load_f("w_rows.txt", 0, -1, 0);
        load_f("p_rows.txt", 1, -1, 0);
        load_f("d_pt.txt", 3, -1, 1); load_f("d_p0.txt", 4, 0, 1); load_f("d_p1.txt", 5, 1, 1); load_f("d_lt.txt", 10, -1, 1);
        load_f("d_ds.txt", 11, 7, 1); hw(15, 6, 0);
        load_f("d_ff.txt", 12, 8, 1); load_f("d_fw.txt", 13, 9, 1); load_f("d_ft.txt", 14, 10, 1);
        load_f("fc_rows.txt", 16, -1, 0);
        load_f("head.txt", 17, -1, 1);
        for (int l = 0; l < 128; l++) hw(2, l, 5189'(img[0][l]));
`ifdef QB_HPW
        $display("QB_CHIP_HPW HPW %0d program + image 0 load: %0d host write cycles (wide port: %0d)", HPW, nwr, nwr_w);
        repeat (10) tick();                                           // narrow port latency before the first h_go
`endif
        // ---- stream
        nfcd = 0;
        cur = 0; ld_img = 1; ld_line = 0; lo_img = 0; img_rd_err = 0; timeout = 0;
        for (cyc = 0; ; cyc++) begin
            #1;
`ifdef QBT_WBSTAT
            ws_sample();
`endif
            h_go = 0; h_we = 0;
            // image end (engine idle again)
            if (cur > 0 && end_c[cur - 1] < 0 && st_idle) begin
                end_c[cur - 1] = cyc; end_now[cur - 1] = int'(now);
`ifndef QBT_GLS                                                          // GLS: no tile-end taps
                for (int i = 0; i < nX[cur - 1]; i++)
                    if (ce_rtl[X_pi[cur - 1][i]][X_tp[cur - 1][i]][X_ct[cur - 1][i]] != X_ce[cur - 1][i]) begin
                        cyc_err[cur - 1]++;
                        if (cyc_err[cur - 1] <= 3) $display("CYCLE_MISMATCH img %0d pass %0d tile %0d ct %0d: rtl ce %0d model %0d",
                            cur - 1, X_pi[cur - 1][i], X_tp[cur - 1][i], X_ct[cur - 1][i],
                            ce_rtl[X_pi[cur - 1][i]][X_tp[cur - 1][i]][X_ct[cur - 1][i]], X_ce[cur - 1][i]);
                    end
`endif
            end
`ifndef QBT_GLS
            if (cur > 0 && free_c[cur - 1] < 0 && dut.img_free) free_c[cur - 1] = cyc;
`else
            if (cur > 0 && free_c[cur - 1] < 0 && st_img_free) free_c[cur - 1] = cyc;
`endif
            // host: go for the next image, else load the next image's lines
`ifdef QBT_SAIF
            if (cur < N && st_idle && ld_img > cur && cur == saif_stop) begin
                $display("QB_CHIP_SAIF stop at the go of img %0d cycle %0d go_prev %0d time %0t", cur, cyc, cur > 0 ? go_c[cur - 1] : -1, $time);
                $finish;
            end
`endif
`ifdef QBT_VSAIF
            if (cur < N && st_idle && ld_img > cur && cur == 1) begin
                $set_toggle_region(tb_qb_chip.dut); $toggle_start; vsaif_c0 = cyc;
            end
            if (cur < N && st_idle && ld_img > cur && cur == 2) begin
                $toggle_stop; $toggle_report(vsaif_fn, 1.0e-12, "tb_qb_chip.dut");
                $display("QB_CHIP_VSAIF %0s cycles %0d..%0d (%0d)", vsaif_fn, vsaif_c0, cyc, cyc - vsaif_c0);
            end
`endif
            if (cur < N && st_idle && ld_img > cur) begin
                h_go = 1; go_c[cur] = cyc;
                for (int p = 0; p < NP; p++) for (int t = 0; t < 64; t++) for (int u = 0; u < 8; u++) ce_rtl[p][t][u] = -1;
                cur++;
            end else if (ld_img < N && ld_img == cur && st_img_free) begin
`ifndef QB_HPW
                h_we = 1; h_sel = 5'd2; h_addr = 11'(ld_line); h_data = 5189'(img[ld_img][ld_line]);
                ld_line++;
                if (ld_line == 128) begin ld_line = 0; ld_img++; end
`else
                h_we = 1; h_sel = 5'd2; h_addr = 11'(ld_line); h_lane = 5'(ld_lane);
                h_data = HPW'(img[ld_img][ld_line][128 * ld_lane +: 128]);
                ld_lane++;
                if (ld_lane == 4) begin ld_lane = 0; ld_line++; end
                if (ld_line == 128) begin ld_line = 0; ldone_c[ld_img] = cyc; ld_img++; end
`endif
            end
`ifndef QBT_GLS
            // tile ends of the running image (time base: now of that image)
            if (dut.ae_eot === 1'b1) ce_rtl[dut.ae_ctx ? dut.ae_pic1 : dut.ae_pic0][dut.dbg_atile][dut.dbg_act_ct] = int'(now) - 2 - AP;
            // IMG must not be read while the host may write it
            if (dut.u_top.m_ren && dut.u_top.m_src == 2'd2 && dut.st_img_free && !h_go) begin
                img_rd_err++;
                if (img_rd_err <= 3) $display("MISMATCH IMG read at cycle %0d while st_img_free", cyc);
            end
            // head overlap: first pq write of each image, FC done of each image
            if (cur > 0 && pq0_c[cur - 1] < 0 && free_c[cur - 1] >= 0 && dut.u_head.pq_wr) pq0_c[cur - 1] = cyc;   // after its stem: not the previous pool tail
            if (dut.u_head.f_done && nfcd < N) begin fcd_c[nfcd] = cyc; nfcd++; end
`endif
            // logits
            if (lo_vld === 1'b1) begin
                if (lo_img >= N) $display("MISMATCH extra logit at cycle %0d", cyc);
                else begin
                    rlg[lo_img][lo_idx] = $signed(lo_val);
                    if ($signed(lo_val) != xlg[lo_img][lo_idx]) begin
                        lg_err[lo_img]++;
                        if (lg_err[lo_img] <= 3) $display("MISMATCH img %0d class %0d logit %0d exp %0d", lo_img, lo_idx,
                                                          $signed(lo_val), xlg[lo_img][lo_idx]);
                    end
                    nlg[lo_img]++;
                    if (nlg[lo_img] == ncls) begin lg_last[lo_img] = cyc; lo_img++; end
                end
            end
            if (lo_img >= N && !st_head_busy) break;
            if (cyc > 6000 * (N + 1)) begin timeout = 1; break; end
            #4 clk = 1; #5 clk = 0;
        end
        // ---- report
        begin
            int tot, pass_all;
            pass_all = (timeout == 0 && err == 0 && img_rd_err == 0);
            for (int i = 0; i < N; i++) begin
                int ok;
                fp = $fopen({dir[i], "/logits_rtl", otag, ".txt"}, "w");
                for (int j = 0; j < ncls; j++) $fwrite(fp, "%0d ", rlg[i][j]);
                $fwrite(fp, "\n"); $fclose(fp);
`ifdef QBT_GLS
                cyc_err[i] = 0;                                  // GLS: no internal taps (tile ends not checked)
`endif
                ok = (lg_err[i] == 0 && nlg[i] == ncls && cyc_err[i] == 0);
                pass_all &= ok;
                $display("QB_CHIP img %0d %s go %0d img_free +%0d end +%0d (rtl_end %0d model %0d delta %0d) interval %0s logits %0d/%0d err %0d tiles %0d cycle_mismatch %0d last_logit +%0d (after end +%0d) %s",
                         i, dir[i], go_c[i], free_c[i] - go_c[i], end_c[i] - go_c[i], end_now[i] + 1, M[i], end_now[i] + 1 - M[i],
                         (i + 1 < N) ? $sformatf("%0d", go_c[i + 1] - go_c[i]) : "-", nlg[i], ncls, lg_err[i], nX[i], cyc_err[i],
                         lg_last[i] - go_c[i], lg_last[i] - end_c[i], ok ? "PASS" : "FAIL");
            end
`ifdef QB_HPW
            for (int i = 0; i + 1 < N; i++)
                $display("QB_CHIP_HPW img %0d loaded (512 writes) from img_free of img %0d (+%0d) to +%0d after its go, %0d cycles before its end (go of img %0d)",
                         i + 1, i, free_c[i] - go_c[i], ldone_c[i + 1] - go_c[i], end_c[i] - ldone_c[i + 1], i + 1);
`endif
            for (int i = 0; i + 1 < N; i++)
                $display("QB_CHIP_OVERLAP img %0d FC done %0d, img %0d first pq write %0d: slack %0d cycles", i, fcd_c[i], i + 1,
                         pq0_c[i + 1], pq0_c[i + 1] - fcd_c[i]);
`ifdef QBT_WBSTAT
            $display("QB_WBSTAT cycles %0d wr_conf %0d classes HQ HQD Z stream r c2 sread", ws_cyc, ws_conf);
            for (int i = 0; i < 7; i++)
                $display("QB_WBSTAT co %0d: %0d %0d %0d %0d %0d %0d %0d", i, ws_co[i][0], ws_co[i][1], ws_co[i][2], ws_co[i][3],
                         ws_co[i][4], ws_co[i][5], ws_co[i][6]);
            for (int i = 0; i < 7; i++)
                $display("QB_WBSTAT mindist %0d: %0d %0d %0d %0d %0d %0d %0d", i, ws_md[i][0], ws_md[i][1], ws_md[i][2], ws_md[i][3],
                         ws_md[i][4], ws_md[i][5], ws_md[i][6]);
            for (int i = 0; i < 4; i++) begin
                string t;  t = "";
                for (int j = 0; j < 16; j++) t = {t, $sformatf(" %0d", ws_h[i][j])};
                $display("QB_WBSTAT hist %0s:%0s", i == 0 ? "HQ_l0" : i == 1 ? "HQD_bq" : i == 2 ? "Z_bz" : "SREAD_srot", t);
            end
`endif
`ifndef QBT_GLS
            $display("QB_CHIP_TB images %0d err %0d img_read_err %0d timeout %0d head_err %0d %s", N, err, img_rd_err, timeout,
                     dut.h_err, pass_all ? "PASS" : "FAIL");
`else
            $display("QB_CHIP_TB GLS images %0d err %0d timeout %0d (logits, intervals; no internal taps) %s", N, err, timeout,
                     pass_all ? "PASS" : "FAIL");
`endif
        end
        $finish;
    end
endmodule
