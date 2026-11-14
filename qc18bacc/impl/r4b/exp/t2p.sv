// R4b SDC check: one rf_2p macro wrapper (QB_TECH) between registers
module t2p (input logic clk, rst_n, input logic ren, we, input logic [7:0] ra, wa, input logic [127:0] wd, wm, output logic [127:0] q);
    logic r_, w_; logic [7:0] ra_, wa_; logic [127:0] wd_, wm_, q_; logic conf;
    always_ff @(posedge clk) begin r_ <= ren; w_ <= we; ra_ <= ra; wa_ <= wa; wd_ <= wd; wm_ <= wm; q <= q_; end
    qbt_rf2p #(128, 256) u_m (.clk, .ren(r_), .ra(ra_), .we(w_), .wa(wa_), .wd(wd_), .wm(wm_), .q(q_), .conf(conf));
endmodule
