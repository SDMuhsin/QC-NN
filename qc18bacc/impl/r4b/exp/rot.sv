// R4b micro-experiment: qb_top's act-port S read rotation (s_q) as written in R4 (rot_a: indexed 32:1 mux per bit)
// vs an explicit group mux + 4-stage log rotator (rot_b).  Registered in / out to time it.
module rot_a (input logic clk, input logic [4095:0] mq, input logic grp, input logic [3:0] rot, output logic [2047:0] q);
    logic [4095:0] m; logic g; logic [3:0] r; logic [2047:0] s;
    always_ff @(posedge clk) begin m <= mq; g <= grp; r <= rot; q <= s; end
    always_comb for (int l = 0; l < 16; l++) s[128 * l +: 128] = m[128 * (16 * g + ((l + r) & 15)) +: 128];
endmodule
module rot_b (input logic clk, input logic [4095:0] mq, input logic grp, input logic [3:0] rot, output logic [2047:0] q);
    logic [4095:0] m; logic g; logic [3:0] r; logic [2047:0] s;
    always_ff @(posedge clk) begin m <= mq; g <= grp; r <= rot; q <= s; end
    always_comb begin
        logic [2047:0] x;
        x = g ? m[4095:2048] : m[2047:0];
        if (r[0]) x = {x[127:0], x[2047:128]};
        if (r[1]) x = {x[255:0], x[2047:256]};
        if (r[2]) x = {x[511:0], x[2047:512]};
        if (r[3]) x = {x[1023:0], x[2047:1024]};
        s = x;
    end
endmodule
