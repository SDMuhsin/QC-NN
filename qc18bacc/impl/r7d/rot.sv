// R7d: the write-back rotators of qb_top QB_TOP_WBR = 1 in isolation (packing expressions copied from qb_top.sv);
// VARIANT HQ | HQD | Z | SHZ (HQD + Z on one payload rotator, Z priority); NOROT: shift forced to 0 (packing only).
module wb_blk (input logic [256*17-1:0] f_y, input logic [32*19-1:0] w_y, input logic [3:0] fct, wct, input logic [6:0] ftp,
               input logic [4:0] fk, wk, input logic z_on, output logic [16*128-1:0] od, oz, output logic [16*8-1:0] oa, oza);
    function automatic logic [3:0] rotd (input logic [2:0] pl); return {pl[2], 1'b0, pl[1:0]}; endfunction
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
    function automatic logic [1023:0] rup16p(input logic [1023:0] x, input logic [3:0] s);   // 64-b payload words
        if (s[0]) x = {x[959:0], x[1023:960]};
        if (s[1]) x = {x[895:0], x[1023:896]};
        if (s[2]) x = {x[767:0], x[1023:768]};
        if (s[3]) x = {x[511:0], x[1023:512]};
        return x;
    endfunction
    logic [3:0] y, l0, bq, bz;  logic [1:0] oy, wy;
    logic [2047:0] xw, xd, xz;  logic [127:0] xa, xc, xza;  logic [1023:0] pq, pz, pr;  logic [127:0] ra;  logic [3:0] sh;
    always_comb begin
        y  = 4'(2 * ftp + 7'(fk[1]));
        l0 = 4'(2 * y + 4'(fk[0]));
        oy = 2'(y >> 1);
        bq = {fct[0], 1'b0, oy};
        wy = 2'(wk >> 3);
        bz = {wct[0], 1'b0, wy};
        for (int pl = 0; pl < 8; pl++)
            for (int j = 0; j < 2; j++) begin
                for (int q = 0; q < 4; q++) for (int c5 = 0; c5 < 32; c5++)
                    xw[128 * (2 * pl + j) + 32 * q + c5] = f_y[17 * (64 * q + 32 * j + c5) + pl];
                for (int h = 0; h < 2; h++) for (int qq = 0; qq < 2; qq++) for (int c5 = 0; c5 < 32; c5++)
                    xd[128 * (4 * j + rotd(3'(pl))) + 64 * h + 32 * qq + c5] = f_y[17 * (64 * (2 * qq) + 32 * j + c5) + pl];
                xa[8 * (2 * pl + j) +: 8] = 8'd128 + 8'(8 * pl) + 8'(2 * fct + 4'(j));
                xc[8 * (4 * j + rotd(3'(pl))) +: 8] = 8'd128 + 8'(2 * pl) + 8'(fct >> 1);
                for (int q = 0; q < 4; q++) for (int cc = 0; cc < 4; cc++) for (int i = 0; i < 8; i++)
                    xz[128 * (4 * j + rotd(3'(pl))) + 32 * q + 8 * cc + i] = w_y[19 * (8 * q + 4 * j + cc) + pl];
                xza[8 * (4 * j + rotd(3'(pl))) +: 8] = 8'd144 + 8'(4 * pl) + 8'(wct >> 1);
            end
`ifdef NOROT
        l0 = '0; bq = '0; bz = '0;
`endif
        od = '0; oa = '0; oz = '0; oza = '0;
`ifdef HQ
        od = rup16(xw, l0); oa = rup8(xa, l0);
`elsif HQD
        od = rup16(xd, bq); oa = rup8(xc, bq);
`elsif Z
        oz = rup16(xz, bz); oza = rup8(xza, bz);
`elsif SHZ
        for (int iz = 0; iz < 16; iz++) begin
            pq[64 * iz +: 64] = xd[128 * iz +: 64];
            pz[64 * iz +: 64] = '0;
            for (int b = 0; b < 16; b++) pz[64 * iz + b] = xz[128 * iz + 8 * b];
            pr[64 * iz +: 16] = z_on ? pz[64 * iz +: 16] : pq[64 * iz +: 16];
            pr[64 * iz + 16 +: 48] = pq[64 * iz + 16 +: 48];
        end
        sh = z_on ? bz : bq;
        pr = rup16p(pr, sh);  ra = rup8(z_on ? xza : xc, sh);
        for (int l = 0; l < 16; l++) begin
            od[128 * l +: 128] = {pr[64 * l +: 64], pr[64 * l +: 64]};  oa[8 * l +: 8] = ra[8 * l +: 8];
            for (int q = 0; q < 4; q++) for (int cc = 0; cc < 4; cc++) for (int i = 0; i < 8; i++)
                oz[128 * l + 32 * q + 8 * cc + i] = pr[64 * l + 4 * q + cc];
            oza[8 * l +: 8] = ra[8 * l +: 8];
        end
`endif
    end
endmodule
