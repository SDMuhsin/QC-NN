// R4b experiment: qb_top's write-back request logic (verbatim always_comb) as a standalone module for an area figure.
module qb_wb_x (
    input  logic clk,
    input  logic [26:0] fo_i, wo_i,
    input  logic f_vld_o, w_vld_o,
    input  logic [4351:0] f_y_i, input logic [255:0] f_b_i, input logic [607:0] w_y_i, input logic [31:0] w_b_i,
    input  logic [95:0] pt [32],
    input  logic [1:0] b2f_n_i, b2_j_i, input logic [2:0] b2w_i, input logic [6:0] b2f_tp_i [2], input logic [3:0] b2f_ct_i [2],
    input  logic [1023:0] b2f_d_i [2],
    output logic [31:0] s_we, output logic [7:0] s_wa [32], output logic [127:0] s_wd [32], s_wm [32],
    output logic [3:0] b_we [2], output logic [6:0] b_wa [2][4], output logic [127:0] b_wd [2][4], b_wm [2][4],
    output logic [63:0] hq, output logic [7:0] hqd, output logic [127:0] hz, output logic cf);
    localparam int NLF = 256, NLW = 32;
    typedef struct packed { logic v; logic hm; logic [2:0] kind; logic [4:0] pi; logic [6:0] tp; logic [3:0] ct; logic [4:0] k; } stp_t;
    function automatic logic [3:0] pt_cfg  (input logic [88:0] w); return w[3:0];   endfunction
    function automatic logic [4:0] pt_nch  (input logic [88:0] w); return w[8:4];   endfunction
    function automatic logic [3:0] pt_nct  (input logic [88:0] w); return w[12:9];  endfunction
    function automatic logic [6:0] pt_ntl  (input logic [88:0] w); return w[19:13]; endfunction
    function automatic logic       pt_i8   (input logic [88:0] w); return w[20];    endfunction
    function automatic logic       pt_stem (input logic [88:0] w); return w[21];    endfunction
    function automatic logic [8:0] pt_sb   (input logic [88:0] w); return w[30:22]; endfunction
    function automatic logic [3:0] pt_kind (input logic [88:0] w); return w[34:31]; endfunction  // stem bc1 bsc bc2 hm wc1 wsc wc2
    function automatic logic [1:0] pt_src  (input logic [88:0] w); return w[36:35]; endfunction  // B1 B2 IMG S
    function automatic logic [9:0] pt_wb   (input logic [88:0] w); return w[46:37]; endfunction
    function automatic logic [4:0] pt_wr   (input logic [88:0] w); return w[51:47]; endfunction
    function automatic logic [2:0] pt_lgc  (input logic [88:0] w); return w[54:52]; endfunction  // log2(C / 64)
    function automatic logic [2:0] pt_lgw  (input logic [88:0] w); return w[57:55]; endfunction  // log2(W out)
    function automatic logic [9:0] pt_pb   (input logic [88:0] w); return w[67:58]; endfunction
    function automatic logic       pt_b1   (input logic [88:0] w); return w[68];    endfunction
    function automatic logic [9:0] pt_lb   (input logic [88:0] w); return w[78:69]; endfunction
    function automatic logic [9:0] pt_lc   (input logic [88:0] w); return w[88:79]; endfunction
    function automatic logic [1:0] h2 (input logic [7:0] a); return a[1:0] ^ a[2:1]; endfunction
    function automatic logic [3:0] rotd (input logic [2:0] pl); return {pl[2], 1'b0, pl[1:0]}; endfunction
    function automatic logic       fsw (input logic [6:0] line); return line[0] ^ line[1]; endfunction
    stp_t fo, wo;  logic [4351:0] f_y; logic [255:0] f_b; logic [607:0] w_y; logic [31:0] w_b;
    logic [1:0] b2f_n, b2_j; logic [2:0] b2w; logic [6:0] b2f_tp [2]; logic [3:0] b2f_ct [2]; logic [1023:0] b2f_d [2];
    always_ff @(posedge clk) begin fo <= fo_i; wo <= wo_i; f_y <= f_y_i; f_b <= f_b_i; w_y <= w_y_i; w_b <= w_b_i;
        b2f_n <= b2f_n_i; b2_j <= b2_j_i; b2w <= b2w_i; b2f_tp <= b2f_tp_i; b2f_ct <= b2f_ct_i; b2f_d <= b2f_d_i; end
    logic [31:0]  sw_en;  logic [7:0] sw_a [32];  logic [127:0] sw_d [32], sw_m [32];  logic sw_conf, bw_conf;
    logic [63:0]  hit_hq;  logic [7:0] hit_hqd;  logic [127:0] hit_z;
    logic [3:0]   bw_en [2];  logic [6:0] bw_a [2][4];  logic [127:0] bw_d [2][4], bw_m [2][4];
    always_comb begin
        sw_en = '0; sw_conf = 1'b0; hit_hq = '0; hit_hqd = '0; hit_z = '0; bw_conf = 1'b0;
        for (int l = 0; l < 32; l++) begin sw_a[l] = '0; sw_d[l] = '0; sw_m[l] = '0; end
        for (int mp = 0; mp < 2; mp++) begin
            bw_en[mp] = '0;
            for (int m = 0; m < 4; m++) begin bw_a[mp][m] = '0; bw_d[mp][m] = '0; bw_m[mp][m] = '0; end
        end
        // ---------------- fused outputs
        if (fo.v && f_vld_o) begin
            logic [88:0] p;
            p = pt[fo.pi];
            if (fo.hm) begin
                // HQ: px = 16 tp + 4 k + q on the 8 x 8 map, y = 2 tp + (k >> 1), x0 = 4 (k & 1)
                logic [3:0] y, l0;
                y  = 4'(2 * fo.tp + 7'(fo.k[1]));
                l0 = 4'(2 * y + 4'(fo.k[0]));
                for (int pl = 0; pl < 8; pl++)
                    for (int j = 0; j < 2; j++) begin
                        logic [127:0] w;  logic [4:0] ln;  logic [5:0] g;
                        g = 6'(2 * fo.ct + j);
                        for (int q = 0; q < 4; q++) for (int c5 = 0; c5 < 32; c5++)
                            w[32 * q + c5] = f_y[17 * (64 * q + 32 * j + c5) + pl];
                        ln = 5'((l0 + 4'(2 * pl + j)) & 4'hf);
                        if (sw_en[ln]) sw_conf = 1'b1;
                        sw_en[ln] = 1'b1; sw_a[ln] = 8'd128 + 8'(8 * pl) + 8'(g); sw_d[ln] = w; sw_m[ln] = '1;
                        if (|w) hit_hq[8 * pl + g] = 1'b1;
                        if (!y[0]) begin                  // HQD: even pixels x0, x0 + 2 (ox = 2 (k & 1) + q / 2)
                            logic [127:0] wd, wm;  logic [3:0] lg;  logic [1:0] oy;  logic [1:0] t3;
                            wd = '0; wm = '0;
                            oy = 2'(y >> 1);
                            t3 = 2'(g);
                            for (int qq = 0; qq < 2; qq++) for (int c5 = 0; c5 < 32; c5++) begin
                                wd[32 * (2 * fo.k[0] + qq) + c5] = f_y[17 * (64 * (2 * qq) + 32 * j + c5) + pl];
                                wm[32 * (2 * fo.k[0] + qq) + c5] = 1'b1;
                            end
                            lg = 4'({t3, oy}) + rotd(3'(pl));
                            ln = 5'(16 + lg);
                            if (sw_en[ln]) sw_conf = 1'b1;
                            sw_en[ln] = 1'b1; sw_a[ln] = 8'd128 + 8'(2 * pl) + 8'(g >> 2); sw_d[ln] = wd; sw_m[ln] = wm;
`ifndef QBT_MUT_FLAG
                            if (|wd) hit_hqd[pl] = 1'b1;
`endif
                        end
                    end
            end else begin
                // stream (stem / sc r / c2 s_out): flat e = px C + 64 ct, per pixel q one address, 8 lanes
                for (int q = 0; q < 4; q++) begin
                    logic [15:0] px;  logic [23:0] e;  logic [7:0] a;  logic [1:0] pg;
                    px = 16'(fo.tp) * 16 + 16'(fo.k) * 4 + 16'(q);
                    e  = (24'(px) << (6 + pt_lgc(p))) + 24'(fo.ct) * 64;
                    a  = e[15:8];
`ifdef QBT_MUT_SWZ
                    pg = (pt_lgc(p) == 3'd0) ? e[7:6] : e[7:6] ^ h2(a);       // mutant: no swizzle at C = 64
`else
                    pg = e[7:6] ^ h2(a);
`endif
                    for (int col = 0; col < 8; col++) begin
                        logic [127:0] w;
                        for (int i = 0; i < 8; i++) w[16 * i +: 16] = f_y[17 * (64 * q + 8 * col + i) +: 16];
                        if (sw_en[8 * pg + col]) sw_conf = 1'b1;
                        sw_en[8 * pg + col] = 1'b1; sw_a[8 * pg + col] = a; sw_d[8 * pg + col] = w; sw_m[8 * pg + col] = '1;
                    end
                end
                // B1 (b1_next): 2 chunk words of 4 px x 32 ch
                if (pt_b1(p)) begin
                    logic [2:0] lw;  logic [15:0] px0;  logic [15:0] y, x0;
                    lw  = pt_lgw(p);
                    px0 = 16'(fo.tp) * 16 + 16'(fo.k) * 4;
                    y   = px0 >> lw;
                    x0  = px0 & ((16'd1 << lw) - 16'd1);
                    for (int j = 0; j < 2; j++) begin
                        logic [15:0] g, pos;  logic [6:0] line;  logic [1:0] m, pm;  logic [127:0] w;
                        g    = 16'(fo.ct) * 2 + 16'(j);
                        pos  = (g << (lw + 5)) + (x0 << 5);
                        line = 7'(4 * y + (pos >> 9));
                        m    = 2'(pos >> 7);
                        pm   = m + 2'(fsw(line));
                        for (int q = 0; q < 4; q++) w[32 * q +: 32] = f_b[64 * q + 32 * j +: 32];
                        if (bw_en[0][pm]) bw_conf = 1'b1;
                        bw_en[0][pm] = 1'b1; bw_a[0][pm] = line; bw_d[0][pm] = w; bw_m[0][pm] = '1;
                    end
                end
            end
        end
        // ---------------- wide outputs (block 6): px = q + 4 (k >> 3), ch = 64 ct + 8 col + 7 - (k & 7)
        if (wo.v && w_vld_o) begin
            logic [2:0] i0;  logic [1:0] y;
            i0 = 3'd7 - 3'(wo.k);
            y  = 2'(wo.k >> 3);
            if (wo.kind == 3'd5) begin                    // b6.c1 -> Z planes (u8)
                for (int pl = 0; pl < 8; pl++)
                    for (int jj = 0; jj < 2; jj++) begin
                        logic [127:0] wd, wm;  logic [5:0] g;  logic [3:0] lg;  logic [4:0] ln;
                        wd = '0; wm = '0;
                        g  = 6'(2 * wo.ct + jj);
                        for (int q = 0; q < 4; q++) for (int cc = 0; cc < 4; cc++) begin
                            wd[32 * q + 8 * cc + i0] = w_y[19 * (8 * q + 4 * jj + cc) + pl];
                            wm[32 * q + 8 * cc + i0] = 1'b1;
                        end
`ifdef QBT_MUT_ZROT
                        lg = 4'({g[1:0], y}) + {1'b0, 3'(pl)};    // mutant: plane rotation 0..7 (collides)
`else
                        lg = 4'({g[1:0], y}) + rotd(3'(pl));
`endif
                        ln = 5'(16 + lg);
                        if (sw_en[ln]) sw_conf = 1'b1;
                        sw_en[ln] = 1'b1; sw_a[ln] = 8'd144 + 8'(4 * pl) + 8'(g >> 2); sw_d[ln] = wd; sw_m[ln] = wm;
                        if (|wd) hit_z[16 * pl + g] = 1'b1;
                    end
            end else if (wo.kind == 3'd6) begin           // b6.sc -> r lo / hi
                logic [6:0] idx;  logic [7:0] a;
                idx = 7'(wo.ct) * 16 + 7'(wo.k[4:1]);
                a   = idx < 7'd64 ? 8'd64 + 8'(idx) : 8'd128 + 8'(idx);
                for (int q = 0; q < 4; q++)
                    for (int h = 0; h < 2; h++) begin
                        logic [127:0] w;  logic [4:0] ln;
                        for (int cc = 0; cc < 4; cc++) begin
                            logic [18:0] r;
                            r = w_y[19 * (8 * q + 4 * h + cc) +: 19];
                            w[32 * cc +: 16]      = r[15:0];
                            w[32 * cc + 16 +: 16] = 16'($signed(r[18:16]));
                        end
                        ln = 5'(8 * wo.k[0] + 2 * q + h);
                        if (sw_en[ln]) sw_conf = 1'b1;
                        sw_en[ln] = 1'b1; sw_a[ln] = a; sw_d[ln] = w; sw_m[ln] = '1;
                    end
            end else if (wo.kind == 3'd7) begin           // b6.c2 -> s (flat, C = 512) + B1 of block 7 (W 4)
                for (int q = 0; q < 4; q++) begin
                    logic [7:0] a;  logic [1:0] pg;
                    a  = 8'(2 * (q + 4 * y)) + 8'(wo.ct >> 2);
                    pg = 2'(wo.ct) ^ h2(a);
                    for (int col = 0; col < 8; col++) begin
                        logic [4:0] ln;
                        ln = 5'(8 * pg + col);
                        if (sw_en[ln]) sw_conf = 1'b1;
                        sw_en[ln] = 1'b1; sw_a[ln] = a;
                        sw_d[ln] = '0; sw_m[ln] = '0;
                        sw_d[ln][16 * i0 +: 16] = w_y[19 * (8 * q + col) +: 16];
                        sw_m[ln][16 * i0 +: 16] = 16'hffff;
                    end
                end
                for (int jj = 0; jj < 2; jj++) begin
                    logic [5:0] g;  logic [6:0] line;  logic [1:0] pm;  logic [127:0] wd, wm;
                    g = 6'(2 * wo.ct + jj);
                    line = 7'(4 * y + (g >> 2));
                    pm = g[1:0] + 2'(fsw(line));
                    wd = '0; wm = '0;
                    for (int q = 0; q < 4; q++) for (int cc = 0; cc < 4; cc++) begin
                        wd[32 * q + 8 * cc + i0] = w_b[8 * q + 4 * jj + cc];
                        wm[32 * q + 8 * cc + i0] = 1'b1;
                    end
                    if (bw_en[0][pm]) bw_conf = 1'b1;
                    bw_en[0][pm] = 1'b1; bw_a[0][pm] = line; bw_d[0][pm] = wd; bw_m[0][pm] = wm;
                end
            end
        end
        // ---------------- b2 writer: line b2_j of the head capture
        if (b2f_n != 2'd0) begin
            logic [6:0] tp;  logic [3:0] ct;
            tp = b2f_tp[0]; ct = b2f_ct[0];
            for (int m = 0; m < 4; m++) begin
                logic [127:0] w;  logic en;  logic [6:0] line;  logic [1:0] pm;
                w = '0; en = 1'b0; line = '0;
                unique case (b2w)
                    3'd5, 3'd4: begin                     // one row, chunk j = b2_j, macro m = x / 4 (x in the tile)
`ifdef QBT_MUT_B2J
                        line = (b2w == 3'd5) ? 7'(4 * (tp >> 1) + 2 * (2 * ct + (b2_j ^ 1)) + (tp & 1))   // mutant
                                             : 7'(4 * tp + 2 * ct + (b2_j ^ 1));
`else
                        line = (b2w == 3'd5) ? 7'(4 * (tp >> 1) + 2 * (2 * ct + b2_j) + (tp & 1))
                                             : 7'(4 * tp + 2 * ct + b2_j);
`endif
                        en = 1'b1;
                        for (int xq = 0; xq < 4; xq++) for (int c5 = 0; c5 < 32; c5++)
                            w[32 * xq + c5] = b2f_d[0][64 * (4 * m + xq) + 32 * b2_j + c5];
                    end
                    3'd3: begin                           // row y = 2 tp + j, macro m = 2 jj + xh
                        line = 7'(4 * (2 * tp + b2_j) + ct);
                        en = 1'b1;
                        for (int xq = 0; xq < 4; xq++) for (int c5 = 0; c5 < 32; c5++)
                            w[32 * xq + c5] = b2f_d[0][64 * (8 * b2_j + 4 * (m & 1) + xq) + 32 * (m >> 1) + c5];
                    end
                    default: begin                        // W 4: row y = 4 tp + j, macros 2 (ct & 1) + jj
                        line = 7'(4 * (4 * tp + b2_j) + (ct >> 1));
                        en = (m >> 1) == (ct & 1);
                        for (int xq = 0; xq < 4; xq++) for (int c5 = 0; c5 < 32; c5++)
                            w[32 * xq + c5] = b2f_d[0][64 * (4 * b2_j + xq) + 32 * (m & 1) + c5];
                    end
                endcase
                pm = 2'(m) + 2'(fsw(line));
                if (en) begin bw_en[1][pm] = 1'b1; bw_a[1][pm] = line; bw_d[1][pm] = w; bw_m[1][pm] = '1; end
            end
        end
    end
    always_ff @(posedge clk) begin
        s_we <= sw_en; s_wa <= sw_a; s_wd <= sw_d; s_wm <= sw_m; b_we <= bw_en; b_wa <= bw_a; b_wd <= bw_d; b_wm <= bw_m;
        hq <= hit_hq; hqd <= hit_hqd; hz <= hit_z; cf <= sw_conf | bw_conf;
    end
endmodule
