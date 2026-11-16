// R7d: HQ write rotator + act-port S-read rotator (QB_TOP_SROT g_srot) on one 2048-b rotator (estimate only, not RTL)
module wb_blk (input logic [256*17-1:0] f_y, input logic [32*128-1:0] s_mq_i, input logic s_grp_q, input logic [3:0] s_rot_q,
               input logic [6:0] ftp, input logic [4:0] fk, input logic sel_hq, output logic [2047:0] s_q);
    logic [3:0] y, l0, s;  logic [2047:0] xw, x;
    always_comb begin
        y  = 4'(2 * ftp + 7'(fk[1]));
        l0 = 4'(2 * y + 4'(fk[0]));
        for (int pl = 0; pl < 8; pl++) for (int j = 0; j < 2; j++) for (int q = 0; q < 4; q++) for (int c5 = 0; c5 < 32; c5++)
            xw[128 * (2 * pl + j) + 32 * q + c5] = f_y[17 * (64 * q + 32 * j + c5) + pl];
        for (int l = 0; l < 16; l++) x[128 * l +: 128] = sel_hq ? xw[128 * l +: 128] : s_grp_q ? s_mq_i[128 * (16 + l) +: 128] : s_mq_i[128 * l +: 128];
        s = sel_hq ? 4'(5'd16 - 5'(l0)) : s_rot_q;                  // HQ: up by l0 = down by 16 - l0
        if (s[0]) x = {x[127:0], x[2047:128]};
        if (s[1]) x = {x[255:0], x[2047:256]};
        if (s[2]) x = {x[511:0], x[2047:512]};
        if (s[3]) x = {x[1023:0], x[2047:1024]};
        s_q = x;
    end
endmodule
