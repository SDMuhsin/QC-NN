// Generic single-port SRAM wrapper: one read OR one write per cycle, registered read data (1-cycle latency,
// held while no read is issued).  Every QC18-ACC memory goes through this module (to be swapped for compiled
// SRAM macros).
module qa_sram #(
  parameter int WORDS = 1024,
  parameter int BITS  = 64,
  parameter int AW    = (WORDS > 1) ? $clog2(WORDS) : 1
) (
  input  logic            clk,
  input  logic            ce,
  input  logic            we,
  input  logic [AW-1:0]   addr,
  input  logic [BITS-1:0] wdata,
  output logic [BITS-1:0] rdata
);
  logic [BITS-1:0] mem [0:WORDS-1];
  always_ff @(posedge clk) begin
    if (ce) begin
      if (we) mem[addr] <= wdata;
      else    rdata     <= mem[addr];
    end
  end
`ifndef SYNTHESIS
  always @(posedge clk) if (ce === 1'b1 && addr >= WORDS) $error("qa_sram %m: address %0d out of range", addr);
`endif
endmodule
