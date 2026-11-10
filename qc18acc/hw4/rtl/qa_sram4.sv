// v4 single-port SRAM wrapper with a registered macro boundary (ARCH.md "v4", fix 1).  The caller drives cen_n /
// wen_n / addr / wdata DIRECTLY from flip-flops (no logic between those flops and the macro pins: qa_bankmem4 /
// qa_actmem4 own them).  The read data has its own output register in the same clock domain:
//   cycle t+1: inputs (flops) at the macro pins, access at the end of t+1;  t+2: macro Q;  t+3: rdata (register,
//   loaded only after a read, so it holds the last read word over writes and idle cycles).
// Write mask: WM groups of BITS / WM bits, wen_n[g] = 0 writes group g; a read has wen_n all ones.
// Behavioural model (hw4/tech/qa_sram4_tech.sv maps it onto the ARM macros with the same ports and behaviour).
module qa_sram4 #(
  parameter int WORDS = 256,
  parameter int BITS  = 128,
  parameter int WM    = 1,
  parameter int AW    = (WORDS > 1) ? $clog2(WORDS) : 1
) (
  input  logic            clk,
  input  logic            cen_n,
  input  logic [WM-1:0]   wen_n,
  input  logic [AW-1:0]   addr,
  input  logic [BITS-1:0] wdata,
  output logic [BITS-1:0] rdata
);
  localparam int GB = BITS / WM;
  logic [BITS-1:0] mem [0:WORDS-1];
  logic [BITS-1:0] q;
  logic rd_q;
  always_ff @(posedge clk) begin
    rd_q <= !cen_n && (&wen_n);
    if (!cen_n) begin
      if (&wen_n) q <= mem[addr];
      else for (int g = 0; g < WM; g++) if (!wen_n[g]) mem[addr][g*GB +: GB] <= wdata[g*GB +: GB];
    end
    if (rd_q) rdata <= q;
  end
`ifndef SYNTHESIS
  always @(posedge clk) if (cen_n === 1'b0 && addr >= WORDS) $error("qa_sram4 %m: address %0d out of range", addr);
`endif
endmodule
