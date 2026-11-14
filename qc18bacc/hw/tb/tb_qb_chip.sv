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
module tb_qb_chip;
    localparam int AP = 1, NP = 32, MAXI = 8;
    logic clk = 0, rst_n = 0, h_we = 0, h_go = 0;
    logic [4:0] h_sel = 0;
    logic [10:0] h_addr = 0;
    logic [5188:0] h_data = 0;
    logic st_idle, st_img_free, st_head_busy, lo_vld, err;
    logic [6:0] lo_idx;
    logic [31:0] lo_val;
    logic [15:0] now;
    qb_chip dut (.*);

    string pdir, dir [MAXI], tag, otag;
    int fp, rc, n, N, cnt, cyc;
    logic [5188:0] w;
    logic [511:0] img [MAXI][128];
    int xlg [MAXI][100], rlg [MAXI][100], nlg [MAXI], lg_last [MAXI], ncls;
    int go_c [MAXI], end_c [MAXI], end_now [MAXI], M [MAXI], M0 [MAXI];
    int X_pi [MAXI][1024], X_tp [MAXI][1024], X_ct [MAXI][1024], X_ce [MAXI][1024], nX [MAXI];
    int ce_rtl [NP][64][8], cyc_err [MAXI], lg_err [MAXI], img_rd_err, cur, ld_img, ld_line, lo_img, timeout;
    int free_c [MAXI], pq0_c [MAXI], fcd_c [MAXI], nfcd;

    task automatic tick(); #5 clk = 1; #5 clk = 0; endtask
    task automatic hw(int sel, int addr, logic [5188:0] data);
        h_we = 1; h_sel = 5'(sel); h_addr = 11'(addr); h_data = data; tick(); h_we = 0;
    endtask
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
            while ($fscanf(fp, "%h\n", w) == 1) begin hw(sel, c, w); c++; end
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
        // ---- stream
        nfcd = 0;
        cur = 0; ld_img = 1; ld_line = 0; lo_img = 0; img_rd_err = 0; timeout = 0;
        for (cyc = 0; ; cyc++) begin
            #1;
            h_go = 0; h_we = 0;
            // image end (engine idle again)
            if (cur > 0 && end_c[cur - 1] < 0 && st_idle) begin
                end_c[cur - 1] = cyc; end_now[cur - 1] = int'(now);
                for (int i = 0; i < nX[cur - 1]; i++)
                    if (ce_rtl[X_pi[cur - 1][i]][X_tp[cur - 1][i]][X_ct[cur - 1][i]] != X_ce[cur - 1][i]) begin
                        cyc_err[cur - 1]++;
                        if (cyc_err[cur - 1] <= 3) $display("CYCLE_MISMATCH img %0d pass %0d tile %0d ct %0d: rtl ce %0d model %0d",
                            cur - 1, X_pi[cur - 1][i], X_tp[cur - 1][i], X_ct[cur - 1][i],
                            ce_rtl[X_pi[cur - 1][i]][X_tp[cur - 1][i]][X_ct[cur - 1][i]], X_ce[cur - 1][i]);
                    end
            end
            if (cur > 0 && free_c[cur - 1] < 0 && dut.img_free) free_c[cur - 1] = cyc;
            // host: go for the next image, else load the next image's lines
            if (cur < N && st_idle && ld_img > cur) begin
                h_go = 1; go_c[cur] = cyc;
                for (int p = 0; p < NP; p++) for (int t = 0; t < 64; t++) for (int u = 0; u < 8; u++) ce_rtl[p][t][u] = -1;
                cur++;
            end else if (ld_img < N && ld_img == cur && st_img_free) begin
                h_we = 1; h_sel = 5'd2; h_addr = 11'(ld_line); h_data = 5189'(img[ld_img][ld_line]);
                ld_line++;
                if (ld_line == 128) begin ld_line = 0; ld_img++; end
            end
            // tile ends of the running image (time base: now of that image)
            if (dut.dbg_aeot === 1'b1) ce_rtl[dut.dbg_actx ? dut.dbg_apic1 : dut.dbg_apic0][dut.dbg_atile][dut.dbg_act_ct] = int'(now) - 2 - AP;
            // IMG must not be read while the host may write it
            if (dut.u_top.m_ren && dut.u_top.m_src == 2'd2 && dut.st_img_free && !h_go) begin
                img_rd_err++;
                if (img_rd_err <= 3) $display("MISMATCH IMG read at cycle %0d while st_img_free", cyc);
            end
            // head overlap: first pq write of each image, FC done of each image
            if (cur > 0 && pq0_c[cur - 1] < 0 && free_c[cur - 1] >= 0 && dut.u_head.pq_wr) pq0_c[cur - 1] = cyc;   // after its stem: not the previous pool tail
            if (dut.u_head.f_done && nfcd < N) begin fcd_c[nfcd] = cyc; nfcd++; end
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
                ok = (lg_err[i] == 0 && nlg[i] == ncls && cyc_err[i] == 0);
                pass_all &= ok;
                $display("QB_CHIP img %0d %s go %0d img_free +%0d end +%0d (rtl_end %0d model %0d delta %0d) interval %0s logits %0d/%0d err %0d tiles %0d cycle_mismatch %0d last_logit +%0d (after end +%0d) %s",
                         i, dir[i], go_c[i], free_c[i] - go_c[i], end_c[i] - go_c[i], end_now[i] + 1, M[i], end_now[i] + 1 - M[i],
                         (i + 1 < N) ? $sformatf("%0d", go_c[i + 1] - go_c[i]) : "-", nlg[i], ncls, lg_err[i], nX[i], cyc_err[i],
                         lg_last[i] - go_c[i], lg_last[i] - end_c[i], ok ? "PASS" : "FAIL");
            end
            for (int i = 0; i + 1 < N; i++)
                $display("QB_CHIP_OVERLAP img %0d FC done %0d, img %0d first pq write %0d: slack %0d cycles", i, fcd_c[i], i + 1,
                         pq0_c[i + 1], pq0_c[i + 1] - fcd_c[i]);
            $display("QB_CHIP_TB images %0d err %0d img_read_err %0d timeout %0d head_err %0d %s", N, err, img_rd_err, timeout,
                     dut.h_err, pass_all ? "PASS" : "FAIL");
        end
        $finish;
    end
endmodule
