// qb_act2: activation supply of qc18bacc, R2b (supply config C of results/supply.md): two qb_act contexts (two array
// passes in flight) sharing the one 512-b binary-map read port, and block-6 int8 maps read from the stream buffer S
// (slice-major, 2048 b / cycle, only executed (plane, chunk) slices, decided by writer-side zero flags).
// R2's qb_act (hw/rtl/qb_act.sv, one context, block 6 from the map port) is unchanged and still built / tested.
//
// Per context (qba2_ctx): latched pass command, loader, 8 x 2048-b line buffer (qba2_lb), sequencer.
//  * binary passes: as R2 (virtual rows, 4 quarter lines / row, window = 8 slots, shift on window advance), but every
//    loader step (quarter line, pad line, skipped odd row) needs a grant of the shared map port;
//  * int8 passes (cfg 8 b6.c1 / 9 b6.sc / 10 b6.c2, c_int8): the line buffer is a FIFO of S words (head = slot 0):
//    a load sequencer walks the executed words of every channel tile (from the flag store, compile/layout_s.py) and
//    reads one S word per grant while fewer than 8 words are buffered; the issue sequencer walks the executed
//    (plane, chunk) items back to back; consumed words are released (shift by 1 / 2 slots) one cycle after the item.
//  * tiles: one tile token (tgo) per scheduler tile ((pixel tile, channel tile); int8: channel tile): its first item
//    issues at max(token, data ready); later items of the tile issue as soon as their data is in the line buffer.
// Shared: map / S port arbiters (per cycle; the request of the older tile wins: smaller l_seq), map / S input
// registers (rdq 512 b, sdq 2048 b), S1 (qb_act2_net.sv: AND-OR over both line buffers), S2 (qba_s2 of qb_act_net.sv),
// act pipe, descriptors (+ ctx).  Both contexts never issue in the same cycle (R3's tokens serialize tiles): err.
//
// Timing (as R2): grant in cycle i -> m_ra / s_ra registered -> macro -> m_q / s_q registered (rdq / sdq) -> line
// buffer write at the end of i + 3 -> usable by an item issued in i + 4.  Item issued in i: d_* at i + 1, act at
// i + 2 + ACT_PIPE; done = 1-cycle pulse at last issue + 3 + ACT_PIPE + 1; a new pass may start the cycle after.
module qb_act2 #(parameter int ACT_PIPE = 1) (
    input  logic          clk,
    input  logic          rst_n,
    // pass command per context (latched on start[c]; the context must be idle; both may start in one cycle)
    input  logic [1:0]       start,
    input  logic [1:0][3:0]  c_cfg,      // 0, 2..10 (gen_act.py table)
    input  logic [1:0][4:0]  c_nchunk,   // 3x3: Cin / 32; 1x1: 1; stem: 2
    input  logic [1:0][3:0]  c_nct,      // channel tiles Cout / 64
    input  logic [1:0][6:0]  c_ntile,    // pixel tiles
    input  logic [1:0]       c_int8,     // block-6 int8 pass: source in S (cfg 8 HQ, 9 HQD, 10 Z)
    input  logic [1:0]       c_stem,
    input  logic [1:0][8:0]  c_base,     // binary: map line of row 0; int8: S address of word 0 (layout_s.py)
    output logic [1:0]    busy,
    output logic [1:0]    done,       // per context, 1-cycle pulse
    // R3 interface per context: tile tokens, load permission (RAW gate) + age of the tile being loaded
    input  logic [1:0]    tgo,
    input  logic [1:0]    l_ok,
    input  logic [15:0]   l_seq0, l_seq1,
    output logic [9:0]    l_pos0, l_pos1,   // loader position: binary virtual rows loaded, int8 S words loaded
    // writer-side zero flags (producer port): f_clr clears bank f_bank; f_we & f_nz sets flag f_idx of bank f_bank
    input  logic          f_clr, f_we, f_nz,
    input  logic [1:0]    f_bank,     // 0 HQ (64: 8 pl + g), 1 HQD (8: pl), 2 Z (128: 16 pl + g)
    input  logic [6:0]    f_idx,
    // binary-map read port (shared)
    output logic          m_ren,
    output logic [8:0]    m_ra,
    output logic          m_ctx,
    input  logic [511:0]  m_q,
    // S read port (lanes 0..15, 2048 b)
    output logic          s_ren,
    output logic [7:0]    s_ra,
    output logic          s_ctx,
    input  logic [2047:0] s_q,
    // item descriptor (d_eot always rides on an item)
    output logic          d_vld, d_first, d_eot, d_neg, d_stem, d_g3n, d_ctx,
    output logic [2:0]    d_plane,
    output logic [3:0]    d_chunk,
    output logic [2:0]    d_ct,
    output logic [5:0]    d_tile,
    // act port
    output logic [4607:0] act,
    output logic          a_vld, a_first, a_eot, a_neg, a_stem, a_g3n, a_ctx,
    output logic [2:0]    a_plane,
    output logic [3:0]    a_chunk,
    output logic [2:0]    a_ct,
    output logic [5:0]    a_tile,
    output logic          err         // both contexts issued in one cycle (R3 protocol violation)
);
    localparam int DW = 1 + 1 + 1 + 1 + 1 + 3 + 4 + 3 + 6;     // first eot neg stem g3n plane chunk ct tile

    // ---------------------------------------------------------------- flag store (200 set-only flops)
    logic [63:0] f_hq;  logic [7:0] f_hqd;  logic [127:0] f_z;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin f_hq <= '0; f_hqd <= '0; f_z <= '0; end
        else begin
            if (f_clr && f_bank == 2'd0) f_hq  <= '0;
            if (f_clr && f_bank == 2'd1) f_hqd <= '0;
            if (f_clr && f_bank == 2'd2) f_z   <= '0;
            if (f_we && f_nz) unique case (f_bank)
                2'd0: f_hq[f_idx[5:0]]  <= 1'b1;
                2'd1: f_hqd[f_idx[2:0]] <= 1'b1;
                default: f_z[f_idx]     <= 1'b1;
            endcase
        end

    // ---------------------------------------------------------------- contexts
    logic [1:0]  lreq, lmap, lren, lgnt, is_v, cdone, cbusy;
    logic [8:0]  laddr [2];
    logic [16383:0] lbf [2];
    logic [38:0] is_sel1 [2];
    logic [3:0]  is_cfg2 [2];
    logic [DW-1:0] is_dsc [2];
    logic [9:0]  lpos [2];
    logic [511:0]  rdq;
    logic [2047:0] sdq;
    for (genvar c = 0; c < 2; c++) begin : g_ctx
        qba2_ctx #(.ACT_PIPE(ACT_PIPE)) u_ctx (
            .clk, .rst_n, .start(start[c]), .c_cfg(c_cfg[c]), .c_nchunk(c_nchunk[c]), .c_nct(c_nct[c]),
            .c_ntile(c_ntile[c]), .c_int8(c_int8[c]), .c_stem(c_stem[c]), .c_base(c_base[c]), .tgo(tgo[c]), .l_ok(l_ok[c]), .f_hq, .f_hqd, .f_z,
            .lreq(lreq[c]), .lmap(lmap[c]), .lren(lren[c]), .laddr(laddr[c]), .lgnt(lgnt[c]), .rdq, .sdq,
            .lbf(lbf[c]), .is_v(is_v[c]), .is_sel1(is_sel1[c]), .is_cfg2(is_cfg2[c]), .is_dsc(is_dsc[c]),
            .busy(cbusy[c]), .done(cdone[c]), .l_pos(lpos[c]));
    end
    assign busy = cbusy;
    assign done = cdone;
    assign l_pos0 = lpos[0];
    assign l_pos1 = lpos[1];

    // ---------------------------------------------------------------- port arbiters: per cycle, older tile first
`ifdef QBA2_MUT_ARB
    wire old1 = l_seq0 < l_seq1;                                    // mutant: younger tile first
`else
    wire old1 = l_seq1 < l_seq0;                                    // context 1 holds the older tile
`endif
    wire [1:0] rq_m = lreq & lmap, rq_s = lreq & ~lmap;
    always_comb begin
        lgnt = '0;
        if (rq_m == 2'b11) lgnt[old1] = 1'b1; else lgnt |= rq_m;
        if (rq_s == 2'b11) lgnt[old1] = 1'b1; else lgnt |= rq_s;
    end
    wire gm = |(lgnt & lmap), gs = |(lgnt & ~lmap);
    wire cm = lgnt[1] & lmap[1], cs = lgnt[1] & ~lmap[1];         // granted context of each port
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin m_ren <= 1'b0; m_ra <= '0; m_ctx <= 1'b0; s_ren <= 1'b0; s_ra <= '0; s_ctx <= 1'b0; end
        else begin
            m_ren <= gm && lren[cm];
            s_ren <= gs;
            if (gm) begin m_ra <= laddr[cm]; m_ctx <= cm; end
            if (gs) begin s_ra <= laddr[cs][7:0]; s_ctx <= cs; end
        end
    always_ff @(posedge clk) begin rdq <= m_q; sdq <= s_q; end

    // ---------------------------------------------------------------- shared patch network + descriptors
    localparam int NS1 = 192;
    logic [38:0]       sel1a, sel1b;
    logic [10:0]       sel2, sel2_1;
    logic [32*NS1-1:0] s1;
    logic [4607:0]     act_q;
    qba2_s1 u_s1 (.clk, .lb0(lbf[0]), .lb1(lbf[1]), .sel1a, .sel1b, .s1);
    qba_s2  u_s2 (.clk, .s1, .sel2(sel2_1), .act(act_q));

    wire ic = is_v[1];
    logic [DW+1:0] dsc;                                            // {vld, ctx, fields}
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin sel1a <= '0; sel1b <= '0; sel2 <= 11'd1; dsc <= '0; err <= 1'b0; end
        else begin
            err   <= err | (&is_v);
`ifdef QBA2_MUT_CTX
            // mutant: S-mode items of context 1 on odd channel tiles select context 0's line buffer
            sel1a <= is_v[0] ? is_sel1[0] : (is_v[1] && is_dsc[1][6] ? {is_sel1[1][38:33], 33'd0} : '0);
            sel1b <= is_v[1] ? (is_dsc[1][6] ? {6'd0, is_sel1[1][32:0]} : is_sel1[1]) : '0;
`else
            sel1a <= is_v[0] ? is_sel1[0] : '0;
            sel1b <= is_v[1] ? is_sel1[1] : '0;
`endif
            if (|is_v) begin
                sel2 <= '0;
                sel2[is_cfg2[ic]] <= 1'b1;
            end
            dsc <= {|is_v, ic, is_dsc[ic]};
        end
    assign {d_vld, d_ctx, d_first, d_eot, d_neg, d_stem, d_g3n, d_plane, d_chunk, d_ct, d_tile} =
        {dsc[DW+1], dsc[DW], dsc[DW-1:0] & {DW{dsc[DW+1]}}};

    logic [DW+1:0] dsc1, dsc2;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin dsc1 <= '0; dsc2 <= '0; sel2_1 <= '0; end
        else begin dsc1 <= {d_vld, d_ctx, d_first, d_eot, d_neg, d_stem, d_g3n, d_plane, d_chunk, d_ct, d_tile};
                   dsc2 <= dsc1; sel2_1 <= sel2; end
    logic [DW+1:0] dscp [ACT_PIPE + 1];
    logic [4607:0] actp [ACT_PIPE + 1];
    assign dscp[0] = dsc2;
    assign actp[0] = act_q;
    for (genvar k = 0; k < ACT_PIPE; k++) begin : g_pipe
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) dscp[k + 1] <= '0; else dscp[k + 1] <= dscp[k];
        qba_areg u_ap (.clk, .d(actp[k]), .q(actp[k + 1]));
    end
    assign act = actp[ACT_PIPE];
    assign {a_vld, a_ctx, a_first, a_eot, a_neg, a_stem, a_g3n, a_plane, a_chunk, a_ct, a_tile} = dscp[ACT_PIPE];
endmodule

// one qb_act2 context: command, loader (map rows or S words), line buffer, sequencer.
module qba2_ctx #(parameter int ACT_PIPE = 1) (
    input  logic            clk, rst_n,
    input  logic            start,
    input  logic [3:0]      c_cfg,
    input  logic [4:0]      c_nchunk,
    input  logic [3:0]      c_nct,
    input  logic [6:0]      c_ntile,
    input  logic            c_int8, c_stem,
    input  logic [8:0]      c_base,
    input  logic            tgo, l_ok,
    input  logic [63:0]     f_hq,
    input  logic [7:0]      f_hqd,
    input  logic [127:0]    f_z,
    output logic            lreq, lmap, lren,
    output logic [8:0]      laddr,
    input  logic            lgnt,
    input  logic [511:0]    rdq,
    input  logic [2047:0]   sdq,
    output logic [16383:0]  lbf,
    output logic            is_v,
    output logic [38:0]     is_sel1,
    output logic [3:0]      is_cfg2,
    output logic [20:0]     is_dsc,       // first eot neg stem g3n plane[3] chunk[4] ct[3] tile[6]
    output logic            busy, done,
    output logic [9:0]      l_pos
);
    // ---------------------------------------------------------------- latched command
    logic [3:0] cfg;  logic [4:0] nchunk;  logic [3:0] nct;  logic [6:0] ntile;  logic int8, stem;  logic [8:0] base;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin cfg <= '0; nchunk <= '0; nct <= '0; ntile <= '0; int8 <= 1'b0; stem <= 1'b0; base <= '0; end
        else if (start) begin
            cfg <= c_cfg; nchunk <= c_nchunk; nct <= c_nct; ntile <= c_ntile; int8 <= c_int8; stem <= c_stem; base <= c_base;
        end

    // ---------------------------------------------------------------- per-cfg constants (binary passes)
    logic [5:0] H;  logic [3:0] K;  logic padL, even, k1;  logic [2:0] adv;  logic [1:0] wcls;
    always_comb begin
        H = 6'd32; K = 4'd3; padL = 1'b1; even = 1'b0; k1 = 1'b0; adv = 3'd1; wcls = 2'd0;
        unique case (cfg)
            4'd0:  begin H = 32; K = 3; padL = 1; adv = 1; wcls = 0; end           // adv applied on odd tiles
            4'd2:  begin H = 32; K = 3; padL = 1; adv = 2; wcls = 0; end
            4'd3:  begin H = 32; K = 2; padL = 0; adv = 2; wcls = 0; even = 1; k1 = 1; end
            4'd4:  begin H = 16; K = 3; padL = 1; adv = 1; wcls = 1; end
            4'd5:  begin H = 16; K = 5; padL = 1; adv = 4; wcls = 1; end
            4'd6:  begin H = 16; K = 4; padL = 0; adv = 4; wcls = 1; even = 1; k1 = 1; end
            4'd7:  begin H = 8;  K = 4; padL = 1; adv = 2; wcls = 2; end
            default: begin H = 4; K = 4; padL = 0; adv = 0; wcls = 3; end          // 10 (b7); 8 / 9 only int8
        endcase
    end
    wire [9:0] vtot = {4'd0, H} + {8'd0, padL, 1'b0};

    typedef enum logic [1:0] {S_IDLE, S_BIN, S_INT, S_FIN} st_t;
    st_t st;
    wire active = (st == S_BIN) || (st == S_INT);

    // ---------------------------------------------------------------- flag views (registered copy of the live store:
    // flags must be final 1 cycle before the consumer's RAW ready / token; timing: cfg mux off the encoder paths)
    logic [63:0]  wbm, wbm_d;                // executed S words of a channel tile (cfg 8: 8 pl + g, 9: pl, 10: 4 pl + q)
    logic [127:0] ibm, ibm_d;                // executed items (16 pl + g)
    always_ff @(posedge clk) begin wbm <= wbm_d; ibm <= ibm_d; end
    always_comb begin
        wbm_d = '0; ibm_d = '0;
        for (int p = 0; p < 8; p++) begin
            unique case (cfg)
                4'd8: begin
                    wbm_d[8 * p +: 8] = f_hq[8 * p +: 8];
                    ibm_d[16 * p +: 8] = f_hq[8 * p +: 8];
                end
                4'd9: begin
                    wbm_d[p] = f_hqd[p];
                    ibm_d[16 * p] = f_hqd[p];
                end
                default: begin
                    for (int q = 0; q < 4; q++) begin
`ifdef QBA2_MUT_FLAG
                        // mutant: slice flag of the neighbouring chunk (g ^ 1)
                        wbm_d[4 * p + q] = |{f_z[16 * p + 4 * q + 0], f_z[16 * p + 4 * q + 1], f_z[16 * p + 4 * q + 2], f_z[16 * p + 4 * q + 3]};
                        for (int j = 0; j < 4; j++) ibm_d[16 * p + 4 * q + j] = f_z[16 * p + 4 * q + (j ^ 1)];
`else
                        wbm_d[4 * p + q] = |f_z[16 * p + 4 * q +: 4];
                        for (int j = 0; j < 4; j++) ibm_d[16 * p + 4 * q + j] = f_z[16 * p + 4 * q + j];
`endif
                    end
                end
            endcase
        end
    end

    // ---------------------------------------------------------------- binary loader (virtual rows, as R2)
    logic [9:0] vb, vbk, vl, vdone;           // vbk = vb + K (registered: window-ready compare off the cfg decode)
    logic [1:0] lq;
    logic [9:0] iy_b;  logic l_pad, l_skip;
    always_comb begin
        iy_b   = vl - {9'd0, padL};
        l_pad  = vl < {9'd0, padL} || iy_b >= {4'd0, H};
        l_skip = even && iy_b[0];
    end
    wire lb_go = active && !int8 && (vl < vtot) && (vl < vb + 10'd8);

    // ---------------------------------------------------------------- int8 S loader (executed words, per channel tile)
    logic [63:0] lrem;  logic lval, lh;  logic [3:0] lct;  logic [9:0] lcnt, rcnt, wdone;
    logic [3:0] nin, nav;                    // buffered words: lcnt - rcnt, wdone - rcnt (registers)
    wire [63:0] lcur = lval ? lrem : wbm;
    logic [5:0] lw;
    always_comb begin
        lw = '0;
        for (int i = 63; i >= 0; i--) if (lcur[i]) lw = 6'(i);
    end
    wire ls_go = active && int8 && (lct < nct) && (lcur != '0) && (nin < 4'd8);
    logic [7:0] saddr;
    always_comb begin
        unique case (cfg)
            4'd8:    saddr = base[7:0] + {2'd0, lw};
            4'd9:    saddr = base[7:0] + {4'd0, lw[2:0], lh};
`ifdef QBA2_MUT_SADDR
            default: saddr = base[7:0] + {3'd0, lw[4:0] ^ 5'd1};        // mutant: Z word of the next chunk quad
`else
            default: saddr = base[7:0] + {3'd0, lw[4:0]};
`endif
        endcase
    end

    assign lreq  = l_ok && (lb_go || ls_go);
    assign lmap  = !int8;
    assign lren  = !(l_pad || l_skip);
    assign laddr = int8 ? {1'b0, saddr} : base + {iy_b[6:0], lq};
    assign l_pos = int8 ? lcnt : vl;

    typedef struct packed { logic v; logic wr; logic s; logic zero; logic last; logic [1:0] q; logic [9:0] row; } ev_t;
    ev_t ev0, ev1, ev2;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            ev0 <= '0; ev1 <= '0; ev2 <= '0; vl <= '0; lq <= '0; lrem <= '0; lval <= 1'b0; lh <= 1'b0; lct <= '0;
            lcnt <= '0;
        end else begin
            ev0 <= '0;
            if (start) begin vl <= '0; lq <= '0; lval <= 1'b0; lh <= 1'b0; lct <= '0; lcnt <= '0; end
            else if (lgnt && !int8) begin
                if (l_skip) begin
                    ev0 <= '{v: 1'b1, wr: 1'b0, s: 1'b0, zero: 1'b0, last: 1'b1, q: 2'd0, row: vl};   // no write
                    vl  <= vl + 10'd1;
                end else begin
                    ev0 <= '{v: 1'b1, wr: 1'b1, s: 1'b0, zero: l_pad, last: (lq == 2'd3), q: lq, row: vl};
                    lq <= lq + 2'd1;
                    if (lq == 2'd3) vl <= vl + 10'd1;
                end
            end else if (lgnt && int8) begin
                logic [63:0] nx;
                ev0  <= '{v: 1'b1, wr: 1'b1, s: 1'b1, zero: 1'b0, last: 1'b1, q: 2'd0, row: lcnt};
                lcnt <= lcnt + 10'd1;
                nx = lcur & ~(64'd1 << lw);
                if (cfg == 4'd9 && !lh) begin lh <= 1'b1; lrem <= lcur; lval <= 1'b1; end
                else begin
                    lh <= 1'b0;
                    if (nx == '0) begin lval <= 1'b0; lct <= lct + 4'd1; end
                    else begin lrem <= nx; lval <= 1'b1; end
                end
            end
            ev1 <= ev0;
            ev2 <= ev1;
        end

    // ---------------------------------------------------------------- line buffer
    logic [2:0] shq;
    wire [9:0] wsl_b = ev2.row - vb;
    wire [3:0] wsl_s = ev2.row[3:0] - rcnt[3:0];
    qba2_lb u_lb (.clk, .shq, .wr_en(ev2.v && ev2.wr),
                  .wsl(ev2.s ? wsl_s[2:0] : wsl_b[2:0]), .wqm(ev2.s ? 4'hf : (4'd1 << ev2.q)), .wzero(ev2.zero),
                  .ws(ev2.s), .rdq, .sdq, .lbf);
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin vdone <= '0; wdone <= '0; end
        else if (start) begin vdone <= '0; wdone <= '0; end
        else begin
            if (ev2.v && !ev2.s && ev2.last) vdone <= ev2.row + 10'd1;
            if (ev2.v && ev2.s) wdone <= wdone + 10'd1;
        end

    // ---------------------------------------------------------------- sequencer
    logic [6:0]  tile;  logic [3:0] ct;  logic [4:0] g;  logic [3:0] fin_cnt;  logic [2:0] tokc;
    logic [127:0] irem;  logic ival;
    wire tok_av = (tokc != 3'd0) || tgo;
    wire bin_ready = vdone >= vbk;
    wire [127:0] icur = ival ? irem : ibm;
    logic [6:0] iw;
    always_comb begin
        iw = '0;
        for (int i = 127; i >= 0; i--) if (icur[i]) iw = 7'(i);
    end
    wire [127:0] inx = icur & ~(128'd1 << iw);
    wire izero = (ibm == '0);                                      // no executed slice: one zero item per channel tile
    wire iready = (cfg == 4'd9) ? (nav >= 4'd2) : (nav >= 4'd1);
    logic [1:0] irel;
    always_comb begin
        unique case (cfg)
            4'd8:    irel = 2'd1;
            4'd9:    irel = 2'd2;
            default: irel = (inx[{iw[6:2], 2'b00} +: 4] == 4'd0) ? 2'd1 : 2'd0;   // last item of its Z word
        endcase
    end

    logic is_first, is_eot, is_zero, consume;  logic [3:0] is_g;  logic [2:0] is_pl;
    always_comb begin
        is_v = 1'b0; is_first = 1'b0; is_eot = 1'b0; is_zero = 1'b0; is_g = g[3:0]; is_pl = '0; consume = 1'b0;
        unique case (st)
            S_BIN: if (bin_ready && (g != 5'd0 || tok_av)) begin
                       is_v = 1'b1; is_first = (g == 5'd0); consume = (g == 5'd0);
                       is_eot = (g == nchunk - 5'd1);
                   end
            S_INT: if (izero) begin
                       if (tok_av) begin is_v = 1'b1; is_first = 1'b1; is_eot = 1'b1; is_zero = 1'b1; consume = 1'b1;
                                         is_g = '0; end
                   end else if (iready && (ival || tok_av)) begin
                       is_v = 1'b1; is_first = !ival; consume = !ival; is_eot = (inx == '0);
                       is_g = iw[3:0]; is_pl = iw[6:4];
                   end
            default: ;
        endcase
    end
    // buffered-word counters (= lcnt - rcnt and wdone - rcnt, kept as registers for timing)
    wire [3:0] nrel = (st == S_INT && is_v && !is_zero) ? {2'd0, irel} : 4'd0;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin nin <= '0; nav <= '0; end
        else if (start) begin nin <= '0; nav <= '0; end
        else begin
            nin <= nin + {3'd0, lgnt && int8} - nrel;
            nav <= nav + {3'd0, ev2.v && ev2.s} - nrel;
        end
    function automatic logic [3:0] k_of(input logic [3:0] c);
        unique case (c)
            4'd3: return 4'd2;
            4'd5: return 4'd5;
            4'd6, 4'd7: return 4'd4;
            4'd0, 4'd2, 4'd4: return 4'd3;
            default: return 4'd4;
        endcase
    endfunction
    wire last_tile = (tile == ntile - 7'd1);
    wire last_ct   = (ct == nct - 4'd1);
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            st <= S_IDLE; shq <= '0; vb <= '0; vbk <= '0; tile <= '0; ct <= '0; g <= '0; fin_cnt <= '0; tokc <= '0; irem <= '0;
            ival <= 1'b0; rcnt <= '0;
        end else begin
            shq <= '0;
            tokc <= tokc + {2'd0, tgo} - {2'd0, consume};
            unique case (st)
                S_IDLE: if (start) begin
                    vb <= '0; vbk <= {6'd0, k_of(c_cfg)}; tile <= '0; ct <= '0; g <= '0; ival <= 1'b0; rcnt <= '0;
                    st <= c_int8 ? S_INT : S_BIN;
                end
                S_BIN: if (is_v) begin
                    if (g != nchunk - 5'd1) g <= g + 5'd1;
                    else begin
                        g <= '0;
                        if (!last_ct) ct <= ct + 4'd1;
                        else begin
                            ct <= '0;
                            if (cfg != 4'd0 || tile[0]) begin
                                vb  <= vb + {7'd0, adv};
                                vbk <= vbk + {7'd0, adv};
                                shq <= {adv == 3'd4, adv == 3'd2, adv == 3'd1};
                            end
                            if (last_tile) begin st <= S_FIN; fin_cnt <= '0; end
                            else tile <= tile + 7'd1;
                        end
                    end
                end
                S_INT: if (is_v) begin
                    if (!is_zero) begin
                        rcnt <= rcnt + {8'd0, irel};
                        shq  <= {1'b0, irel == 2'd2, irel == 2'd1};
                    end
                    if (is_eot) begin
                        ival <= 1'b0;
                        if (last_ct) begin st <= S_FIN; fin_cnt <= '0; end
                        else ct <= ct + 4'd1;
                    end else begin irem <= inx; ival <= 1'b1; end
                end
                S_FIN: begin
                    fin_cnt <= fin_cnt + 4'd1;
                    if (fin_cnt == 4'(3 + ACT_PIPE)) st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    assign busy = st != S_IDLE;
    assign done = (st == S_FIN) && (fin_cnt == 4'(3 + ACT_PIPE));

    // ---------------------------------------------------------------- issue outputs (registered in qb_act2)
    always_comb begin
        is_sel1 = '0;
        if (is_v && !is_zero) begin
            if (int8)    is_sel1[cfg == 4'd8 ? 33 : cfg == 4'd9 ? 34 : 35 + is_g[1:0]] = 1'b1;
            else if (k1) is_sel1[cfg == 4'd3 ? 30 : 31] = 1'b1;
            else         is_sel1[(wcls == 0 ? 0 : wcls == 1 ? 2 : wcls == 2 ? 6 : 14) + is_g] = 1'b1;
        end
    end
    assign is_cfg2 = (cfg == 4'd0 && tile[0]) ? 4'd1 : cfg;
    assign is_dsc  = {is_first, is_eot,
                      int8 && is_pl == 3'd7 && !is_zero,                       // neg
                      stem, stem && is_g == 4'd1,                              // stem, g3n
                      int8 ? is_pl : (stem ? {is_g[0], 2'b00} : 3'd0),         // plane
                      is_g, ct[2:0], tile[5:0]};
endmodule

// line buffer of one context: 8 slots x 2048 b; per edge: shift by shq (one-hot 1 / 2 / 4 slots toward slot 0), then
// write slot wsl (post-shift coordinates): binary = one 512-b quarter (wqm one-hot) of the map line rdq (or zeros),
// int8 = the whole slot from the S word sdq.
module qba2_lb (
    input  logic           clk,
    input  logic [2:0]     shq,
    input  logic           wr_en,
    input  logic [2:0]     wsl,
    input  logic [3:0]     wqm,
    input  logic           wzero,
    input  logic           ws,
    input  logic [511:0]   rdq,
    input  logic [2047:0]  sdq,
    output logic [16383:0] lbf);
    logic [2047:0] lb [8];
    logic [2047:0] wd;
    always_comb for (int s = 0; s < 8; s++) lbf[2048 * s +: 2048] = lb[s];
    always_comb wd = wzero ? 2048'd0 : ws ? sdq : {4{rdq}};
    always_ff @(posedge clk) begin
        for (int s = 0; s < 8; s++) begin
            logic [2047:0] nx;
            nx = lb[s];
            if (shq[0] && s + 1 < 8) nx = lb[(s + 1) % 8];
            if (shq[1] && s + 2 < 8) nx = lb[(s + 2) % 8];
            if (shq[2] && s + 4 < 8) nx = lb[(s + 4) % 8];
            for (int q = 0; q < 4; q++)
                if (wr_en && wsl == 3'(s) && wqm[q]) nx[512 * q +: 512] = wd[512 * q +: 512];
            lb[s] <= nx;
        end
    end
endmodule
