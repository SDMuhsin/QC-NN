module wb_blk (input logic [32*128-1:0] s_mq_i, input logic s_grp_q, input logic [3:0] s_rot_q, output logic [2047:0] s_q);
    // qb_top QB_TOP_SROT g_srot body (group mux + 4-stage log rotator), verbatim
    logic [127:0] s_mq [32];  always_comb for (int l = 0; l < 32; l++) s_mq[l] = s_mq_i[128 * l +: 128];
        always_comb begin
            logic [2047:0] x;
            for (int l = 0; l < 16; l++) x[128 * l +: 128] = s_grp_q ? s_mq[16 + l] : s_mq[l];
            if (s_rot_q[0]) x = {x[127:0], x[2047:128]};
            if (s_rot_q[1]) x = {x[255:0], x[2047:256]};
            if (s_rot_q[2]) x = {x[511:0], x[2047:512]};
            if (s_rot_q[3]) x = {x[1023:0], x[2047:1024]};
            s_q = x;
        end
endmodule
