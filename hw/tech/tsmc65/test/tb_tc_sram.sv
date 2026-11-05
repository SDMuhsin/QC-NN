// Self-checking test of the TSMC 65 nm tc_sram overlay against a reference model of the tc_sram contract
// (1 port, latency 1, byte enables, rdata updated by reads only), random operations, for the shapes the Snitch
// cluster uses: 1024 x 64 / byte 8 (HD-SRAM macro), 16 x 256 (2 RF macros, full-word writes), 16 x 41 (flip-flops).
// Simulate with the macro models ($QC_MC_OUT/<inst>/<inst>.v); prints PASS / FAIL per shape.
`timescale 1ns/1ps
module tb_tc_sram_shape #(
  parameter int unsigned Words = 1024,
  parameter int unsigned Width = 64,
  parameter int unsigned ByteW = 8,
  parameter bit          FullWordWrites = 0,
  parameter int unsigned NumOps = 20000
) (
  input  logic clk,
  input  logic rst_n,
  output logic done,
  output int   errors
);
  localparam int unsigned AW = $clog2(Words);
  localparam int unsigned BW = (Width + ByteW - 1) / ByteW;
  logic req, we;
  logic [AW-1:0] addr;
  logic [Width-1:0] wdata, rdata, exp_q;
  logic [BW-1:0] be;
  logic [Width-1:0] ref_mem [Words];
  bit reads_seen;

  tc_sram #(.NumWords(Words), .DataWidth(Width), .ByteWidth(ByteW), .NumPorts(1), .Latency(1)) i_dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .we_i(we), .addr_i(addr), .wdata_i(wdata), .be_i(be),
    .rdata_o(rdata)
  );

  function automatic logic [Width-1:0] rnd();
    logic [Width-1:0] v;
    for (int i = 0; i < Width; i += 32) v[i+:32] = $urandom;
    return v;
  endfunction

  initial begin
    done = 0; errors = 0; reads_seen = 0;
    req = 0; we = 0; addr = '0; wdata = '0; be = '0;
    for (int i = 0; i < Words; i++) ref_mem[i] = '0;
    @(posedge rst_n);
    // initialise every word (the macros power up with unknown contents)
    for (int i = 0; i < Words; i++) begin
      @(negedge clk);
      req = 1; we = 1; addr = i; wdata = rnd(); be = '1; ref_mem[i] = wdata;
    end
    for (int n = 0; n < NumOps; n++) begin
      @(negedge clk);
      // check the read data of the previous cycle(s): rdata must equal the last read result at all times
      if (reads_seen && rdata !== exp_q) begin
        errors++;
        if (errors < 10) $display("%m: op %0d rdata %h expected %h", n, rdata, exp_q);
      end
      req = ($urandom % 4) != 0;
      we  = $urandom % 2;
      addr = $urandom % Words;
      wdata = rnd();
      be = FullWordWrites ? '1 : BW'($urandom);
      if (req && we) begin
        for (int b = 0; b < Width; b++) if (be[b / ByteW]) ref_mem[addr][b] = wdata[b];
      end
      @(posedge clk);
      #0.001;
      if (req && !we) begin
        exp_q = ref_mem[addr]; reads_seen = 1;
      end
    end
    @(negedge clk); req = 0;
    done = 1;
    $display("%s tc_sram %0dx%0d byte %0d: %0d errors in %0d ops", errors ? "FAIL" : "PASS", Words, Width, ByteW,
             errors, NumOps);
  end
endmodule

module tb_tc_sram;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  initial #22 rst_n = 1;
  logic [2:0] done;
  int e0, e1, e2;
  tb_tc_sram_shape #(.Words(1024), .Width(64), .ByteW(8))                    i_tcdm  (.clk, .rst_n, .done(done[0]), .errors(e0));
  tb_tc_sram_shape #(.Words(16),   .Width(256), .ByteW(8), .FullWordWrites(1)) i_icdat (.clk, .rst_n, .done(done[1]), .errors(e1));
  tb_tc_sram_shape #(.Words(16),   .Width(41), .ByteW(8))                    i_ictag (.clk, .rst_n, .done(done[2]), .errors(e2));
  initial begin
    wait (&done);
    $display("%s tb_tc_sram total errors %0d", (e0 + e1 + e2) ? "FAIL" : "PASS", e0 + e1 + e2);
    $finish;
  end
endmodule
