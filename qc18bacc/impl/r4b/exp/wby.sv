// R4b experiment: qb_top's QB_TOP_WBR S write-request logic as a standalone module for an area figure.
module qb_wb_y (
    input  logic clk,
    input  logic [26:0] fo_i, wo_i,
    input  logic f_vld_o, w_vld_o,
    input  logic [4351:0] f_y_i, input logic [607:0] w_y_i,
    input  logic [95:0] pt [32],
    output logic [31:0] s_we, output logic [7:0] s_wa [32], output logic [127:0] s_wd [32], s_wm [32],
    output logic [63:0] hq, output logic [7:0] hqd, output logic [127:0] hz, output logic cf);
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
    stp_t fo, wo;  logic [4351:0] f_y; logic [607:0] w_y;
    always_ff @(posedge clk) begin fo <= fo_i; wo <= wo_i; f_y <= f_y_i; w_y <= w_y_i; end
    logic [31:0]  wr_en;  logic [7:0] wr_a [32];  logic [127:0] wr_d [32], wr_m [32];  logic wr_conf;
    // rotate 16 lanes up by s (new lane l = old lane l - s mod 16): 128-b words / 8-b addresses
    function automatic logic [2047:0] rup16(input logic [2047:0] x, input logic [3:0] s);
        if (s[0]) x = {x[1919:0], x[2047:1920]};
        if (s[1]) x = {x[1791:0], x[2047:1792]};
        if (s[2]) x = {x[1535:0], x[2047:1536]};
        if (s[3]) x = {x[1023:0], x[2047:1024]};
        return x;
    endfunction
    function automatic logic [127:0] rup8(input logic [127:0] x, input logic [3:0] s);
        if (s[0]) x = {x[119:0], x[127:120]};
        if (s[1]) x = {x[111:0], x[127:112]};
        if (s[2]) x = {x[95:0], x[127:96]};
        if (s[3]) x = {x[63:0], x[127:64]};
        return x;
    endfunction
    logic [63:0]  wr_hq;  logic [7:0] wr_hqd;  logic [127:0] wr_z;
    always_comb begin
        logic [31:0]  ef, ew;  logic [7:0] af [32], aw [32];  logic [127:0] df [32], mf [32], dw [32], mw [32];
        logic         cf, cw;
        ef = '0; ew = '0; cf = 1'b0; cw = 1'b0; wr_hq = '0; wr_hqd = '0; wr_z = '0;
        for (int l = 0; l < 32; l++) begin af[l] = '0; aw[l] = '0; df[l] = '0; mf[l] = '0; dw[l] = '0; mw[l] = '0; end
        // ---- fused
        if (fo.v && f_vld_o) begin
            logic [88:0] p;
            p = pt[fo.pi];
            if (fo.hm) begin
                logic [3:0] y, l0, bq;  logic [1:0] oy;
                logic [2047:0] xw, xd;  logic [127:0] xa, xc;               // 16 lanes x (128-b word, 8-b address)
                y  = 4'(2 * fo.tp + 7'(fo.k[1]));
                l0 = 4'(2 * y + 4'(fo.k[0]));
                oy = 2'(y >> 1);
                bq = {fo.ct[0], 1'b0, oy};                                // HQD base 8 ct[0] + oy
                for (int pl = 0; pl < 8; pl++)
                    for (int j = 0; j < 2; j++) begin
                        logic [127:0] w, v;  int ix, iz;
                        ix = 2 * pl + j;                                    // HQ word index (lane l0 + ix)
                        iz = 4 * j + int'(rotd(3'(pl)));                    // HQD word index (lane 16 + bq + iz)
                        for (int q = 0; q < 4; q++) for (int c5 = 0; c5 < 32; c5++)
                            w[32 * q + c5] = f_y[17 * (64 * q + 32 * j + c5) + pl];
                        for (int h = 0; h < 2; h++) for (int qq = 0; qq < 2; qq++) for (int c5 = 0; c5 < 32; c5++)
                            v[64 * h + 32 * qq + c5] = f_y[17 * (64 * (2 * qq) + 32 * j + c5) + pl];
                        xw[128 * ix +: 128] = w;  xa[8 * ix +: 8] = 8'd128 + 8'(8 * pl) + 8'(2 * fo.ct + 4'(j));
                        xd[128 * iz +: 128] = v;  xc[8 * iz +: 8] = 8'd128 + 8'(2 * pl) + 8'(fo.ct >> 1);
                        if (|w) wr_hq[8 * pl + 2 * fo.ct + j] = 1'b1;
                        if (|v[63:0] && !y[0]) wr_hqd[pl] = 1'b1;
                    end
                xw = rup16(xw, l0);  xa = rup8(xa, l0);                     // word ix -> lane l0 + ix
                xd = rup16(xd, bq);  xc = rup8(xc, bq);                     // word iz -> lane 16 + bq + iz
                for (int l = 0; l < 16; l++) begin
                    ef[l] = 1'b1; df[l] = xw[128 * l +: 128]; mf[l] = '1; af[l] = xa[8 * l +: 8];
                    ef[16 + l] = !y[0]; df[16 + l] = xd[128 * l +: 128]; af[16 + l] = xc[8 * l +: 8];
                    mf[16 + l] = fo.k[0] ? {64'hffffffffffffffff, 64'd0} : {64'd0, 64'hffffffffffffffff};
                end
            end else begin
                logic [7:0] a [4];  logic [1:0] pg [4];
                for (int q = 0; q < 4; q++) begin
                    logic [15:0] px;  logic [23:0] e;
                    px = 16'(fo.tp) * 16 + 16'(fo.k) * 4 + 16'(q);
                    e  = (24'(px) << (6 + pt_lgc(p))) + 24'(fo.ct) * 64;
                    a[q] = e[15:8];
`ifdef QBT_MUT_SWZ
                    pg[q] = (pt_lgc(p) == 3'd0) ? e[7:6] : e[7:6] ^ h2(a[q]);
`else
                    pg[q] = e[7:6] ^ h2(a[q]);
`endif
                end
                for (int q = 0; q < 4; q++) for (int r = q + 1; r < 4; r++) if (pg[q] == pg[r]) cf = 1'b1;
                for (int G = 0; G < 4; G++)
                    for (int col = 0; col < 8; col++) begin
                        logic [127:0] w;  logic [7:0] aa;  logic en;
                        w = '0; aa = '0; en = 1'b0;
                        for (int q = 0; q < 4; q++)
                            if (pg[q] == 2'(G)) begin
                                en = 1'b1; aa = aa | a[q];
                                for (int i = 0; i < 8; i++) w[16 * i +: 16] = w[16 * i +: 16] | f_y[17 * (64 * q + 8 * col + i) +: 16];
                            end
                        ef[8 * G + col] = en; df[8 * G + col] = w; mf[8 * G + col] = '1; af[8 * G + col] = aa;
                    end
            end
        end
        // ---- wide (block 6)
        if (wo.v && w_vld_o) begin
            logic [2:0] i0;  logic [1:0] y;  logic [127:0] mi;
            i0 = 3'd7 - 3'(wo.k);
            y  = 2'(wo.k >> 3);
            for (int b = 0; b < 128; b++) mi[b] = 3'(b % 8) == i0;          // bit i0 of every byte
            if (wo.kind == 3'd5) begin                                      // b6.c1 -> Z planes
                logic [3:0] bz;  logic [2047:0] xz;  logic [127:0] xa;
                bz = {wo.ct[0], 1'b0, y};
                for (int pl = 0; pl < 8; pl++)
                    for (int jj = 0; jj < 2; jj++) begin
                        logic [127:0] w;  logic [15:0] h;  int iz;
                        iz = 4 * jj + int'(rotd(3'(pl)));
                        for (int q = 0; q < 4; q++) for (int cc = 0; cc < 4; cc++) begin
                            h[4 * q + cc] = w_y[19 * (8 * q + 4 * jj + cc) + pl];
                            for (int i = 0; i < 8; i++) w[32 * q + 8 * cc + i] = h[4 * q + cc];
                        end
                        xz[128 * iz +: 128] = w;  xa[8 * iz +: 8] = 8'd144 + 8'(4 * pl) + 8'(wo.ct >> 1);
                        if (|h) wr_z[16 * pl + 2 * wo.ct + jj] = 1'b1;
                    end
                xz = rup16(xz, bz);  xa = rup8(xa, bz);                     // word iz -> lane 16 + bz + iz
                for (int l = 0; l < 16; l++) begin
                    ew[16 + l] = 1'b1; dw[16 + l] = xz[128 * l +: 128]; mw[16 + l] = mi; aw[16 + l] = xa[8 * l +: 8];
                end
            end else if (wo.kind == 3'd6) begin                             // b6.sc -> r lo / hi
                logic [6:0] idx;  logic [7:0] a;
                idx = 7'(wo.ct) * 16 + 7'(wo.k[4:1]);
                a   = idx < 7'd64 ? 8'd64 + 8'(idx) : 8'd128 + 8'(idx);
                for (int l = 0; l < 16; l++) begin
                    logic [127:0] w;
                    for (int cc = 0; cc < 4; cc++) begin
                        logic [18:0] r;
                        r = w_y[19 * (8 * ((l & 7) >> 1) + 4 * (l & 1) + cc) +: 19];
                        w[32 * cc +: 16] = r[15:0];
                        w[32 * cc + 16 +: 16] = 16'($signed(r[18:16]));
                    end
                    ew[l] = (l >> 3) == int'(wo.k[0]); dw[l] = w; mw[l] = '1; aw[l] = a;
                end
            end else if (wo.kind == 3'd7) begin                             // b6.c2 -> s
                logic [7:0] a [4];  logic [1:0] pg [4];  logic [127:0] m16;
                for (int b = 0; b < 128; b++) m16[b] = 3'(b / 16) == i0;
                for (int q = 0; q < 4; q++) begin
                    a[q]  = 8'(2 * (q + 4 * y)) + 8'(wo.ct >> 2);
                    pg[q] = 2'(wo.ct) ^ h2(a[q]);
                end
                for (int q = 0; q < 4; q++) for (int r = q + 1; r < 4; r++) if (pg[q] == pg[r]) cw = 1'b1;
                for (int G = 0; G < 4; G++)
                    for (int col = 0; col < 8; col++) begin
                        logic [15:0] v;  logic [7:0] aa;  logic en;
                        v = '0; aa = '0; en = 1'b0;
                        for (int q = 0; q < 4; q++)
                            if (pg[q] == 2'(G)) begin en = 1'b1; aa = aa | a[q]; v = v | w_y[19 * (8 * q + col) +: 16]; end
                        ew[8 * G + col] = en; dw[8 * G + col] = {8{v}}; mw[8 * G + col] = m16; aw[8 * G + col] = aa;
                    end
            end
        end
        wr_en = ef | ew;
        wr_conf = cf | cw | ((ef & ew) != '0);
        for (int l = 0; l < 32; l++) begin
            wr_d[l] = ew[l] ? dw[l] : (ef[l] ? df[l] : '0);  wr_m[l] = ew[l] ? mw[l] : (ef[l] ? mf[l] : '0);
            wr_a[l] = ew[l] ? aw[l] : (ef[l] ? af[l] : '0);
        end
    end
    always_ff @(posedge clk) begin
        s_we <= wr_en; s_wa <= wr_a; s_wd <= wr_d; s_wm <= wr_m; hq <= wr_hq; hqd <= wr_hqd; hz <= wr_z; cf <= wr_conf;
    end
endmodule
