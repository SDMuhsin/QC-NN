module tb_rot;
    logic clk = 0; logic [4095:0] mq; logic grp; logic [3:0] rot; logic [2047:0] qa, qb; int bad = 0;
    rot_a ua (.clk, .mq, .grp, .rot, .q(qa)); rot_b ub (.clk, .mq, .grp, .rot, .q(qb));
    initial begin
        for (int i = 0; i < 2000; i++) begin
            for (int w = 0; w < 128; w++) mq[32 * w +: 32] = $urandom; grp = $urandom; rot = $urandom;
            #5 clk = 1; #5 clk = 0; #5 clk = 1; #5 clk = 0;
            if (qa !== qb) bad++;
        end
        $display("ROT_EQ bad %0d", bad); $finish;
    end
endmodule
