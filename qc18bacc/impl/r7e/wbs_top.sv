// R7e: registered shell around wbs.sv wb_blk for DC (inputs and outputs registered: identical flops in old / new, so the
// area delta is the write-back + S-read rotator logic; timing = register to register through the rotators).
module wbs_top (input logic clk, input logic [256*17-1:0] f_y, input logic [32*19-1:0] w_y, input logic [3:0] fct, wct,
                input logic [6:0] ftp, input logic [4:0] fk, wk, input logic hm, z_on, input logic [32*128-1:0] s_mq_i,
                input logic s_grp_q, input logic [3:0] s_rot_q, output logic [2047:0] s_q, output logic [16*128-1:0] dlo, dhi,
                output logic [16*8-1:0] alo, ahi);
    logic [256*17-1:0] f_y_r;  logic [32*19-1:0] w_y_r;  logic [3:0] fct_r, wct_r, s_rot_r;  logic [6:0] ftp_r;
    logic [4:0] fk_r, wk_r;  logic hm_r, z_on_r, s_grp_r;  logic [32*128-1:0] s_mq_r;
    logic [2047:0] s_q_c, dlo_c, dhi_c;  logic [127:0] alo_c, ahi_c;
    always_ff @(posedge clk) begin
        f_y_r <= f_y; w_y_r <= w_y; fct_r <= fct; wct_r <= wct; ftp_r <= ftp; fk_r <= fk; wk_r <= wk; hm_r <= hm;
        z_on_r <= z_on; s_mq_r <= s_mq_i; s_grp_r <= s_grp_q; s_rot_r <= s_rot_q;
        s_q <= s_q_c; dlo <= dlo_c; dhi <= dhi_c; alo <= alo_c; ahi <= ahi_c;
    end
    wb_blk u_wb (.f_y(f_y_r), .w_y(w_y_r), .fct(fct_r), .wct(wct_r), .ftp(ftp_r), .fk(fk_r), .wk(wk_r), .hm(hm_r),
                 .z_on(z_on_r), .s_mq_i(s_mq_r), .s_grp_q(s_grp_r), .s_rot_q(s_rot_r), .s_q(s_q_c), .dlo(dlo_c),
                 .dhi(dhi_c), .alo(alo_c), .ahi(ahi_c));
endmodule
