// qb_pe: one PE of the 1-bit-activation QC accelerator = one output pixel x 8 output channels (lanes), bit-serial
// over weight planes, popcount datapath.
//
// Per cycle: KB activation bytes a[j] (bit n = input channel n of block j, 1-bit activations) and KB 10-b codes
// c[j] = {k1[2:0], t1[1:0], k2[2:0], t2[1:0]} (trit 00 = 0, 01 = +1, 11 = -1, 10 = 0 (unused)); term (k, t)
// contributes t * a[j][(i + k) mod 8] to lane i.  plane[2:0] / neg: this cycle's terms have weight 2^plane
// (neg = 1: -2^plane, two's-complement MSB plane).
//   x_{j,n,i} = (t != 0) & (a[j][(i+k) mod 8] ^ (t == -1)),  u_i = popcount_{j,n} x,  nneg = #(t == -1)
//   sum_i = u_i - nneg  (= sum_{j,n} t * a, range [-2KB, 2KB]),   acc_i = (first ? 0 : acc_i) +/- (sum_i << plane)
// (mod 2^ACC_W).  valid = 0: acc holds.  capture: shadow <= acc (value BEFORE this cycle's term, so capture of the
// finished tile goes together with first of the next one: zero-bubble tile switch).  shift (capture has priority):
// lane-serial drain chain shadow[0] <= sh_in, shadow[i] <= shadow[i-1], sh_out = shadow[7] (lane 7 leaves first;
// sh_out of one PE drives sh_in of the next).
// Pipeline: S0 input registers (all inputs) -> S1 popcount registers (u_i, nneg) -> S2 acc / shadow update.
// Every control acts at S2, so an input of cycle n reaches acc / shadow at the clock edge n+2 (sh_out after it).
// rst_n: synchronous, clears the control pipeline (valid / capture / shift) only.
module qb_pe #(
    parameter int KB    = 16,
    parameter int ACC_W = 20
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic [KB*8-1:0]    a,
    input  logic [KB*10-1:0]   c,
    input  logic [2:0]         plane,
    input  logic               neg,
    input  logic               valid,
    input  logic               first,
    input  logic               capture,
    input  logic               shift,
    input  logic [ACC_W-1:0]   sh_in,
    output logic [ACC_W-1:0]   sh_out
);
    localparam int PW = $clog2(2*KB + 1);   // popcount width

    // ---- S0: input registers
    logic [KB*8-1:0]  a_q;
    logic [KB*10-1:0] c_q;
    logic [2:0]       plane_q;
    logic             neg_q, first_q, valid_q, cap_q, shift_q;
    logic [ACC_W-1:0] shin_q;
    qb_pe_in #(.KB(KB), .ACC_W(ACC_W)) u_in (
        .clk, .rst_n, .a, .c, .plane, .neg, .valid, .first, .capture, .shift, .sh_in,
        .a_q, .c_q, .plane_q, .neg_q, .valid_q, .first_q, .cap_q, .shift_q, .shin_q);

    // ---- S1: popcount (rotate / xor / count + registers u, nneg)
    logic [8*PW-1:0]  u_q;
    logic [PW-1:0]    nneg_q;
    qb_pe_pop #(.KB(KB), .PW(PW)) u_pop (.clk, .a(a_q), .c(c_q), .u_q, .nneg_q);

    // control pipeline S0 -> S1
    logic [2:0]       plane_p;
    logic             neg_p, first_p, valid_p, cap_p, shift_p;
    logic [ACC_W-1:0] shin_p;
    always_ff @(posedge clk) begin
        plane_p <= plane_q; neg_p <= neg_q; first_p <= first_q; shin_p <= shin_q;
        if (!rst_n) begin valid_p <= 1'b0; cap_p <= 1'b0; shift_p <= 1'b0; end
        else        begin valid_p <= valid_q; cap_p <= cap_q; shift_p <= shift_q; end
    end

    // ---- S2: accumulators + shadow chain
    qb_pe_acc #(.ACC_W(ACC_W), .PW(PW)) u_acc (
        .clk, .u(u_q), .nneg(nneg_q), .plane(plane_p), .neg(neg_p), .first(first_p), .valid(valid_p),
        .capture(cap_p), .shift(shift_p), .sh_in(shin_p), .sh_out);
endmodule

module qb_pe_in #(
    parameter int KB    = 16,
    parameter int ACC_W = 20
) (
    input  logic               clk, rst_n,
    input  logic [KB*8-1:0]    a,
    input  logic [KB*10-1:0]   c,
    input  logic [2:0]         plane,
    input  logic               neg, valid, first, capture, shift,
    input  logic [ACC_W-1:0]   sh_in,
    output logic [KB*8-1:0]    a_q,
    output logic [KB*10-1:0]   c_q,
    output logic [2:0]         plane_q,
    output logic               neg_q, valid_q, first_q, cap_q, shift_q,
    output logic [ACC_W-1:0]   shin_q
);
    always_ff @(posedge clk) begin
        a_q <= a; c_q <= c; plane_q <= plane; neg_q <= neg; first_q <= first; shin_q <= sh_in;
        if (!rst_n) begin valid_q <= 1'b0; cap_q <= 1'b0; shift_q <= 1'b0; end
        else        begin valid_q <= valid; cap_q <= capture; shift_q <= shift; end
    end
endmodule

module qb_pe_pop #(
    parameter int KB = 16,
    parameter int PW = 6
) (
    input  logic               clk,
    input  logic [KB*8-1:0]    a,
    input  logic [KB*10-1:0]   c,
    output logic [8*PW-1:0]    u_q,
    output logic [PW-1:0]      nneg_q
);
    logic [2*KB-1:0] x [8];   // x[i][term]
    logic [2*KB-1:0] ng;      // term is -1
    always_comb begin
        for (int j = 0; j < KB; j++) begin
            for (int n = 0; n < 2; n++) begin
                logic [2:0]  k;
                logic [1:0]  t;
                logic [15:0] aa;
                logic [7:0]  rot;
                k = (n == 0) ? c[10*j+7 +: 3] : c[10*j+2 +: 3];
                t = (n == 0) ? c[10*j+5 +: 2] : c[10*j+0 +: 2];
                aa  = {a[8*j +: 8], a[8*j +: 8]};
                rot = aa[k +: 8];                     // rot[i] = a[(i + k) mod 8]
                ng[2*j+n] = t[1] & t[0];
                for (int i = 0; i < 8; i++) x[i][2*j+n] = t[0] & (rot[i] ^ t[1]);
            end
        end
    end
    logic [PW-1:0] u [8];
    logic [PW-1:0] nn;
    always_comb begin
        for (int i = 0; i < 8; i++) u[i] = PW'($countones(x[i]));
        nn = PW'($countones(ng));
    end
    always_ff @(posedge clk) begin
        for (int i = 0; i < 8; i++) u_q[PW*i +: PW] <= u[i];
        nneg_q <= nn;
    end
endmodule

module qb_pe_acc #(
    parameter int ACC_W = 20,
    parameter int PW    = 6
) (
    input  logic               clk,
    input  logic [8*PW-1:0]    u,
    input  logic [PW-1:0]      nneg,
    input  logic [2:0]         plane,
    input  logic               neg, first, valid, capture, shift,
    input  logic [ACC_W-1:0]   sh_in,
    output logic [ACC_W-1:0]   sh_out
);
    logic [ACC_W-1:0] acc [8];
    logic [ACC_W-1:0] shd [8];
    always_ff @(posedge clk) begin
        for (int i = 0; i < 8; i++) begin
            if (valid) begin
                logic signed [PW:0]      s;
                logic        [ACC_W-1:0] sv, base;
                s    = $signed({1'b0, u[PW*i +: PW]}) - $signed({1'b0, nneg});
                sv   = ACC_W'(s) << plane;             // sign-extended, then shifted (mod 2^ACC_W)
                base = first ? '0 : acc[i];
                acc[i] <= base + (sv ^ {ACC_W{neg}}) + ACC_W'(neg);
            end
        end
        if (capture)    for (int i = 0; i < 8; i++) shd[i] <= acc[i];
        else if (shift) begin
            shd[0] <= sh_in;
            for (int i = 1; i < 8; i++) shd[i] <= shd[i-1];
        end
    end
    assign sh_out = shd[7];
endmodule
