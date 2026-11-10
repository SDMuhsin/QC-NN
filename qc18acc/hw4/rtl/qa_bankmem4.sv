// v4 wide single-port memory of BANKS qa_sram4 macros (bank = addr / BANK_WORDS): weight halves 3 x 4096 x 80,
// params 2 x 4096 x 72, descriptors 1 x 256 x 32.  Registered macro boundary (ARCH.md "v4", fix 1):
//   cycle t   request (ce, we, addr, wdata) presented combinationally by the requester (port muxing in qa_top)
//   cycle t+1 input flops: one shared address / write-data register and one CEN flop per macro drive the macro pins
//             directly (the host write data into the weight / param macros is launched from these flops)
//   cycle t+2 macro Q;  t+3 per-macro output registers (qa_sram4), bank select (sel delayed to t+3) -> rdata
// Read latency MLAT = 3: rdata of a read requested in cycle t is valid in cycle t+3 and held until the next read.
module qa_bankmem4 #(
  parameter int BANKS = 3,
  parameter int BANK_WORDS = 4096,
  parameter int BITS = 80,
  parameter int AW = (BANKS * BANK_WORDS > 1) ? $clog2(BANKS * BANK_WORDS) : 1
) (
  input  logic            clk,
  input  logic            rst_n,
  input  logic            ce,
  input  logic            we,
  input  logic [AW-1:0]   addr,
  input  logic [BITS-1:0] wdata,
  output logic [BITS-1:0] rdata
);
  localparam int BAW = $clog2(BANK_WORDS);
  localparam int SW = (BANKS > 1) ? $clog2(BANKS) : 1;
  logic [BITS-1:0] rd [0:BANKS-1];
  logic [BANKS-1:0] cen_q;                         // input flops at the macro pins
  logic wen_q;
  logic [BAW-1:0] addr_q;
  logic [BITS-1:0] wdata_q;
  logic [SW-1:0] sel1, sel2, sel3;
  logic rd1, rd2;
  wire  [SW-1:0] sel = (BANKS > 1) ? SW'(addr / BANK_WORDS) : '0;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cen_q <= '1; rd1 <= 1'b0; rd2 <= 1'b0;
    end else begin
      for (int b = 0; b < BANKS; b++) cen_q[b] <= !(ce && sel == SW'(b));
      rd1 <= ce && !we; rd2 <= rd1;
    end
    if (ce) begin wen_q <= !we; addr_q <= BAW'(addr % BANK_WORDS); end
    if (ce && we) wdata_q <= wdata;
    if (ce && !we) sel1 <= sel;
    if (rd1) sel2 <= sel1;
    if (rd2) sel3 <= sel2;
  end
  genvar b;
  for (b = 0; b < BANKS; b++) begin : g_bank
    qa_sram4 #(.WORDS(BANK_WORDS), .BITS(BITS), .WM(1)) u_ram (
      .clk(clk), .cen_n(cen_q[b]), .wen_n(wen_q), .addr(addr_q), .wdata(wdata_q), .rdata(rd[b]));
  end
  assign rdata = rd[sel3];
`ifndef SYNTHESIS
  always @(posedge clk) if (ce === 1'b1 && addr >= BANKS * BANK_WORDS) $error("qa_bankmem4 %m: address %0d out of range", addr);
`endif
endmodule
