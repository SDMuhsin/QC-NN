// Single-port wide memory built from BANKS qa_sram instances of BANK_WORDS words (bank = addr / BANK_WORDS).
// Used for the weight SRAM (6 x 4096 x 80 b) and the param SRAM (2 x 4096 x 72 b).  Read latency 1 cycle
// (bank select registered, data mux after the macro output).
module qa_bankmem #(
  parameter int BANKS = 6,
  parameter int BANK_WORDS = 4096,
  parameter int BITS = 80,
  parameter int AW = $clog2(BANKS * BANK_WORDS)
) (
  input  logic            clk,
  input  logic            ce,
  input  logic            we,
  input  logic [AW-1:0]   addr,
  input  logic [BITS-1:0] wdata,
  output logic [BITS-1:0] rdata
);
  localparam int BAW = $clog2(BANK_WORDS);
  localparam int SW = (BANKS > 1) ? $clog2(BANKS) : 1;
  logic [BITS-1:0] rd [0:BANKS-1];
  logic [SW-1:0] sel_q;
  wire  [SW-1:0] sel = SW'(addr / BANK_WORDS);
  genvar b;
  for (b = 0; b < BANKS; b++) begin : g_bank
    qa_sram #(.WORDS(BANK_WORDS), .BITS(BITS)) u_ram (
      .clk(clk), .ce(ce && sel == SW'(b)), .we(we), .addr(BAW'(addr % BANK_WORDS)), .wdata(wdata), .rdata(rd[b]));
  end
  always_ff @(posedge clk) if (ce && !we) sel_q <= sel;
  assign rdata = rd[sel_q];
`ifndef SYNTHESIS
  always @(posedge clk) if (ce === 1'b1 && addr >= BANKS * BANK_WORDS) $error("qa_bankmem %m: address %0d out of range", addr);
`endif
endmodule
