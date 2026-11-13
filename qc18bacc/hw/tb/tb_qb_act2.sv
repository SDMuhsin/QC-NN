// Image-level bench of qb_act2 (R2b) against export_act2.py vectors (Verilator --binary).  +dir=<image dir>.
// Replays compile/supply.py config C for the image (sched.txt): pass commands on the model's context at the model's
// context start, tile tokens at the model's scheduled tile starts, load permissions (RAW ready + age per tile, in
// commit order), producer flag writes before the first RAW ready of every block-6 pass.  The map and S macros are
// behavioural 1-cycle-read memories holding, per context, the source of the pass that context runs (mem_<pi> /
// smem_<pi>; every read happens after its RAW ready by the model's hazard-checked schedule).  Checks: every act-port
// item (descriptor + 4608-b act) and end-of-tile marker of every pass in order vs exp_<pi>.txt (attributed by a_ctx),
// and every tile's end (last issue + 1, from the a_eot cycle) vs the model's ce (cycle-exact).
module tb_qb_act2;
    localparam int AP = 1, MAXE = 4096, MAXC = 40000;
    logic clk = 0, rst_n = 0;
    logic [1:0] start = 0, c_int8 = 0, c_stem = 0;
    logic [1:0][3:0] c_cfg = 0, c_nct = 0;
    logic [1:0][4:0] c_nchunk = 0;
    logic [1:0][6:0] c_ntile = 0;
    logic [1:0][8:0] c_base = 0;
    logic [1:0] busy, done, tgo = 0, l_ok = 0;
    logic [15:0] l_seq0 = 0, l_seq1 = 0;
    logic [9:0] l_pos0, l_pos1;
    logic f_clr = 0, f_we = 0, f_nz = 0;
    logic [1:0] f_bank = 0;
    logic [6:0] f_idx = 0;
    logic m_ren, m_ctx, s_ren, s_ctx, err;
    logic [8:0] m_ra;
    logic [7:0] s_ra;
    logic [511:0] m_q;
    logic [2047:0] s_q;
    logic d_vld, d_first, d_eot, d_neg, d_stem, d_g3n, d_ctx, a_vld, a_first, a_eot, a_neg, a_stem, a_g3n, a_ctx;
    logic [2:0] d_plane, a_plane, d_ct, a_ct;
    logic [3:0] d_chunk, a_chunk;
    logic [5:0] d_tile, a_tile;
    logic [4607:0] act;

    qb_act2 #(.ACT_PIPE(AP)) dut (.*);

    // behavioural macros (per context: the source of its current pass)
    logic [511:0]  mline [2][256];
    logic [2047:0] sword [2][256];
    logic [511:0]  mq_r, tmpm [256];
    logic [2047:0] tmps [256];
    logic [2047:0] sq_r;
    always_ff @(posedge clk) begin
        if (m_ren) mq_r <= mline[m_ctx][m_ra[7:0]];
        if (s_ren) sq_r <= sword[s_ctx][s_ra];
    end
    assign m_q = mq_r;
    assign s_q = sq_r;

    // pass table
    int npass, p_pi [32], p_cfg [32], p_nch [32], p_nct [32], p_ntl [32], p_i8 [32], p_stm [32], p_nit [32];
    string p_nm [32];
    int pidx [64];                      // pi -> row
    // schedule
    int nP, P_cyc [64], P_ctx [64], P_pi [64];
    int nT, T_cyc [MAXE], T_ctx [MAXE];
    int nF, F_cyc [8], F_bank [8], F_pi [8];
    int nL [64], L_pos [64][256], L_ra [64][256], L_seq [64][256];
    int nX, X_pi [MAXE], X_tp [MAXE], X_ct [MAXE], X_ce [MAXE];
    int ce_rtl [64][64][8];
    // flags being written
    int fl_bank [256], fl_idx [256], fl_nz [256], nfl, fl_ptr, fl_cyc;
    string dir, tag, nm;
    int fp, rc, a, b, c, d, e, f, g, h, i2, j2, cyc, pc, tc, ok;
    int cur_pi [2], lptr [2], fe [2], ncmp [64], nerr [64], nev [64], tot_err, tot_cmp, cyc_err, nbit;
    int first_iss [64], last_iss [64], done_cyc [64], nsr [64], s_first [64], s_last [64], nconf_m, nconf_s, nboth;
    int xf, xpl, xng, xst, xg3, xch, xct, xtl;
    logic [4607:0] xact;

    function automatic string fname(string kind, int pi);
        return $sformatf("%s/%s_%0d.txt", dir, kind, pi);
    endfunction

    task automatic load_pass(int cx, int pi);
        int r;
        r = pidx[pi];
        for (int k = 0; k < 256; k++) begin mline[cx][k] = '0; sword[cx][k] = '0; end
        if (p_i8[r]) begin
            $readmemh(fname("smem", pi), tmps);
            for (int k = 0; k < 256; k++) sword[cx][k] = tmps[k];
        end else begin
            for (int k = 0; k < 256; k++) tmpm[k] = '0;
            $readmemh(fname("mem", pi), tmpm, 0, 127);
            for (int k = 0; k < 256; k++) mline[cx][k] = tmpm[k];
        end
        if (fe[cx] != 0) $fclose(fe[cx]);
        fe[cx] = $fopen(fname("exp", pi), "r");
        cur_pi[cx] = pi;
        lptr[cx] = 0;
        c_cfg[cx] = 4'(p_cfg[r]); c_nchunk[cx] = 5'(p_nch[r]); c_nct[cx] = 4'(p_nct[r]); c_ntile[cx] = 7'(p_ntl[r]);
        c_int8[cx] = p_i8[r][0]; c_stem[cx] = p_stm[r][0];
        c_base[cx] = !p_i8[r] ? 9'd0 : p_cfg[r] == 8 ? 9'd128 : p_cfg[r] == 9 ? 9'd192 : 9'd208;
        start[cx] = 1'b1;
        if (busy[cx]) begin tot_err++; $display("MISMATCH cycle %0d: context %0d busy at pass %0d start", cyc, cx, pi); end
    endtask

    task automatic check_item(int cx);
        int pi;
        pi = cur_pi[cx];
        rc = $fscanf(fe[cx], "%s", tag);
        if (rc != 1 || tag != "I") begin
            nerr[pi]++; if (nerr[pi] <= 3) $display("MISMATCH pass %0d cycle %0d: unexpected item (exp %s)", pi, cyc, tag);
            return;
        end
        rc = $fscanf(fe[cx], "%d %d %d %d %d %d %d %d %h\n", xf, xpl, xng, xst, xg3, xch, xct, xtl, xact);
        ncmp[pi]++;
        if ({a_first, a_plane, a_neg, a_stem, a_g3n, a_chunk, a_ct, a_tile} !==
            {xf[0], 3'(xpl), xng[0], xst[0], xg3[0], 4'(xch), 3'(xct), 6'(xtl)} || act !== xact) begin
            nerr[pi]++;
            nbit += $countones(act ^ xact);
            if (nerr[pi] <= 3)
                $display("MISMATCH pass %0d item %0d cycle %0d: f %0d pl %0d ng %0d ch %0d ct %0d t %0d (exp %0d %0d %0d %0d %0d %0d) act bits %0d",
                         pi, ncmp[pi], cyc, a_first, a_plane, a_neg, a_chunk, a_ct, a_tile, xf, xpl, xng, xch, xct, xtl,
                         $countones(act ^ xact));
        end
    endtask

    task automatic check_eot(int cx);
        int pi;
        pi = cur_pi[cx];
        rc = $fscanf(fe[cx], "%s", tag);
        if (rc != 1 || tag != "E") begin
            nerr[pi]++; if (nerr[pi] <= 3) $display("MISMATCH pass %0d cycle %0d: unexpected end of tile (exp %s)", pi, cyc, tag);
            return;
        end
        rc = $fscanf(fe[cx], "%d %d\n", xct, xtl);
        nev[pi]++;
        if (a_ct !== 3'(xct) || a_tile !== 6'(xtl)) begin
            nerr[pi]++; if (nerr[pi] <= 3) $display("MISMATCH pass %0d eot ct %0d tile %0d exp %0d %0d", pi, a_ct, a_tile, xct, xtl);
        end
        ce_rtl[pi][a_tile][a_ct] = cyc - 2 - AP;                    // issue = cyc - 3 - AP; ce = issue + 1
    endtask

    task automatic tick();
        #5 clk = 1; #5 clk = 0;
    endtask

    initial begin
        if (!$value$plusargs("dir=%s", dir)) $fatal(1, "need +dir=");
        fp = $fopen({dir, "/passes_act.txt"}, "r");
        npass = 0;
        while ($fscanf(fp, "%d %s %d %d %d %d %d %d %d %d\n", a, nm, b, c, d, e, f, g, h, i2) == 10) begin
            p_pi[npass] = a; p_nm[npass] = nm; p_cfg[npass] = b; p_nch[npass] = c; p_nct[npass] = d; p_ntl[npass] = e;
            p_i8[npass] = f; p_stm[npass] = g; p_nit[npass] = i2; pidx[a] = npass; npass++;
        end
        $fclose(fp);
        for (int k = 0; k < 64; k++) begin
            nL[k] = 0; ncmp[k] = 0; nerr[k] = 0; nev[k] = 0; first_iss[k] = -1; last_iss[k] = -1; done_cyc[k] = -1; nsr[k] = 0; s_first[k] = -1; s_last[k] = -1;
            for (int t = 0; t < 64; t++) for (int u = 0; u < 8; u++) ce_rtl[k][t][u] = -1;
        end
        nP = 0; nT = 0; nF = 0; nX = 0;
        fp = $fopen({dir, "/sched.txt"}, "r");
        while ($fscanf(fp, "%s", tag) == 1) begin
            case (tag)
                "P": begin rc = $fscanf(fp, "%d %d %d\n", a, b, c); P_cyc[nP] = a; P_ctx[nP] = b; P_pi[nP] = c; nP++; end
                "T": begin rc = $fscanf(fp, "%d %d %d %d %d\n", a, b, c, d, e); T_cyc[nT] = a; T_ctx[nT] = b; nT++; end
                "F": begin rc = $fscanf(fp, "%d %d %d\n", a, b, c); F_cyc[nF] = a; F_bank[nF] = b; F_pi[nF] = c; nF++; end
                "L": begin rc = $fscanf(fp, "%d %d %d %d\n", a, b, c, d);
                           L_pos[a][nL[a]] = b; L_ra[a][nL[a]] = c; L_seq[a][nL[a]] = d; nL[a]++; end
                "X": begin rc = $fscanf(fp, "%d %d %d %d\n", a, b, c, d); X_pi[nX] = a; X_tp[nX] = b; X_ct[nX] = c;
                           X_ce[nX] = d; nX++; end
                default: $fatal(1, "bad sched tag %s", tag);
            endcase
        end
        $fclose(fp);
        cur_pi = '{-1, -1}; fe = '{0, 0}; lptr = '{0, 0};
        tot_err = 0; tot_cmp = 0; cyc_err = 0; nbit = 0; nconf_m = 0; nconf_s = 0; nboth = 0; nfl = 0; fl_ptr = 0; fl_cyc = -1;
        tick(); tick(); rst_n = 1; tick();
        pc = 0; tc = 0;
        for (cyc = 0; cyc < MAXC; cyc++) begin
            // ---- inputs of this cycle
            start = 0; tgo = '0; f_clr = 0; f_we = 0;
            while (pc < nP && P_cyc[pc] == cyc) begin load_pass(P_ctx[pc], P_pi[pc]); pc++; end
            while (tc < nT && T_cyc[tc] == cyc) begin
                if (tgo[T_ctx[tc]]) begin tot_err++; $display("MISMATCH two tokens of one context in cycle %0d", cyc); end
                tgo[T_ctx[tc]] = 1'b1; tc++;
            end
            for (int k = 0; k < nF; k++) if (F_cyc[k] == cyc) begin
                // producer: clear the bank, then one flag per cycle
                fp = $fopen(fname("flags", F_pi[k]), "r");
                nfl = 0;
                while ($fscanf(fp, "%d %d %d\n", a, b, c) == 3) begin fl_bank[nfl] = a; fl_idx[nfl] = b; fl_nz[nfl] = c; nfl++; end
                $fclose(fp);
                fl_ptr = 0; f_clr = 1; f_bank = 2'(F_bank[k]);
            end
            if (!f_clr && fl_ptr < nfl) begin
                f_we = 1; f_bank = 2'(fl_bank[fl_ptr]); f_idx = 7'(fl_idx[fl_ptr]); f_nz = fl_nz[fl_ptr][0]; fl_ptr++;
            end
            for (int cx = 0; cx < 2; cx++) begin
                int pi, pos;
                pi = cur_pi[cx];
                pos = cx == 0 ? int'(l_pos0) : int'(l_pos1);
                ok = 0;
                if (pi >= 0 && !start[cx]) begin
                    while (lptr[cx] < nL[pi] && L_pos[pi][lptr[cx]] <= pos) lptr[cx]++;
                    if (lptr[cx] < nL[pi]) begin
                        ok = cyc >= L_ra[pi][lptr[cx]];
                        if (cx == 0) l_seq0 = 16'(L_seq[pi][lptr[cx]]); else l_seq1 = 16'(L_seq[pi][lptr[cx]]);
                    end
                end
                l_ok[cx] = ok[0];
            end
            #1;
            // ---- outputs of this cycle
            if (a_vld === 1'b1) begin
                if (first_iss[cur_pi[a_ctx]] < 0) first_iss[cur_pi[a_ctx]] = cyc - 3 - AP;
                last_iss[cur_pi[a_ctx]] = cyc - 3 - AP;
                check_item(a_ctx);
            end
            if (a_eot === 1'b1) check_eot(a_ctx);
            if (dut.rq_m == 2'b11) nconf_m++;
            if (dut.rq_s == 2'b11) nconf_s++;
            if (dut.gm && dut.gs) nboth++;
            if (s_ren === 1'b1) begin
                nsr[cur_pi[s_ctx]]++;
                if (s_first[cur_pi[s_ctx]] < 0) s_first[cur_pi[s_ctx]] = cyc - 1;
                s_last[cur_pi[s_ctx]] = cyc - 1;
            end
            for (int cx = 0; cx < 2; cx++) if (done[cx] === 1'b1) done_cyc[cur_pi[cx]] = cyc;
            #4 clk = 1; #5 clk = 0;
            if (pc >= nP && done_cyc[cur_pi[0]] >= 0 && done_cyc[cur_pi[1]] >= 0 && !busy[0] && !busy[1]) break;
        end
        // ---- per-tile cycle check
        for (int k = 0; k < nX; k++)
            if (ce_rtl[X_pi[k]][X_tp[k]][X_ct[k]] != X_ce[k]) begin
                cyc_err++;
                if (cyc_err <= 5) $display("CYCLE_MISMATCH pass %0d tile %0d ct %0d: rtl ce %0d model ce %0d", X_pi[k], X_tp[k],
                                           X_ct[k], ce_rtl[X_pi[k]][X_tp[k]][X_ct[k]], X_ce[k]);
            end
        for (int r = 0; r < npass; r++) begin
            int pi, mce, mfirst;
            pi = p_pi[r];
            if (ncmp[pi] != p_nit[r]) begin nerr[pi]++; $display("MISMATCH pass %0d: %0d items, expected %0d", pi, ncmp[pi], p_nit[r]); end
            mce = -1;
            for (int k = 0; k < nX; k++) if (X_pi[k] == pi && X_ce[k] > mce) mce = X_ce[k];
            $display("QB_ACT2 pass %0d %s cfg %0d items %0d eot %0d first_issue %0d last_issue %0d model_last %0d done %0d s_reads %0d s_span %0d %0d err %0d",
                     pi, p_nm[r], p_cfg[r], ncmp[pi], nev[pi], first_iss[pi], last_iss[pi], mce - 1, done_cyc[pi], nsr[pi],
                     s_first[pi], s_last[pi], nerr[pi]);
            tot_err += nerr[pi]; tot_cmp += ncmp[pi];
        end
        if (err) begin tot_err++; $display("MISMATCH both contexts issued in one cycle"); end
        $display("QB_ACT2_ARB map_both_req %0d s_both_req %0d map_and_s_grant %0d", nconf_m, nconf_s, nboth);
        $display("QB_ACT2_TB %s items %0d act_bytes %0d tiles %0d cycle_mismatch %0d last_cycle %0d errors %0d %s", dir,
                 tot_cmp, tot_cmp * 576, nX, cyc_err, cyc, tot_err,
                 (tot_err == 0 && cyc_err == 0 && tot_cmp > 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
