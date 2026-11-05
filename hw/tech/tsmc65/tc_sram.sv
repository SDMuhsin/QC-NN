// TSMC 65 nm (tcbn65gplus) implementation of the tech_cells_generic `tc_sram`, same parameters and ports.
//
// Each port maps to compiled ARM single-port macros (hw/tech/tsmc65/macros.txt, flow/tsmc65/sram/mc_gen.sh):
//   NumWords 1024, DataWidth 64, ByteWidth 8 -> qc_sp_1024x64m8 (HD-SRAM, byte write mask)       Snitch TCDM bank
//   NumWords 16,   DataWidth k*128, be all 1 -> k x qc_rf_16x128m1 side by side (register file)   icache data set
//   anything else                            -> flip-flop array (tc_sram_qc_ff)                   e.g. icache tags
// Only NumPorts = 1, Latency = 1 shapes use macros.  The RF macros have no write mask: their shape is used only
// where the caller writes whole words (be_i = '1); simulation checks that.
//
// Macro pins: CEN / GWEN / WEN active low, EMA (extra margin) tied to 000 (the fastest legal setting; chimera ties
// its SRAM config inputs to 0 as well, and impl_i of tc_sram_impl is ignored), RETN tied inactive (1).
//
// Read-data contract of tc_sram: rdata_o changes only after a read and stays stable over writes.  The macros are
// write-through (Q shows D after a write), so every macro port has a small adapter (tc_sram_qc_hold): on a write that
// follows a read, the last read data is captured and rdata_o switches to that register until the next read.
module tc_sram #(
  parameter int unsigned NumWords     = 32'd1024,
  parameter int unsigned DataWidth    = 32'd128,
  parameter int unsigned ByteWidth    = 32'd8,
  parameter int unsigned NumPorts     = 32'd2,
  parameter int unsigned Latency      = 32'd1,
  parameter              SimInit      = "none",
  parameter bit          PrintSimCfg  = 1'b0,
  parameter              ImplKey      = "none",
  // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
  parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth   = (DataWidth + ByteWidth - 32'd1) / ByteWidth,
  parameter type         addr_t    = logic [AddrWidth-1:0],
  parameter type         data_t    = logic [DataWidth-1:0],
  parameter type         be_t      = logic [BeWidth-1:0]
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic  [NumPorts-1:0] req_i,
  input  logic  [NumPorts-1:0] we_i,
  input  addr_t [NumPorts-1:0] addr_i,
  input  data_t [NumPorts-1:0] wdata_i,
  input  be_t   [NumPorts-1:0] be_i,
  output data_t [NumPorts-1:0] rdata_o
);

  localparam bit OnePort  = (NumPorts == 1) && (Latency == 1);
  localparam bit IsTcdm   = OnePort && NumWords == 1024 && DataWidth == 64 && ByteWidth == 8;
  localparam bit IsRf16   = OnePort && NumWords == 16 && DataWidth % 128 == 0;
  localparam int RfTiles  = DataWidth / 128;

  if (IsTcdm || IsRf16) begin : gen_macro
    data_t q;      // macro read data (write-through)

    if (IsTcdm) begin : gen_sp_1024x64
      logic [7:0] wen_n;
      for (genvar b = 0; b < 8; b++) begin : gen_wen
        assign wen_n[b] = ~be_i[0][b];
      end
      qc_sp_1024x64m8 i_macro (
        .Q   (q),
        .CLK (clk_i),
        .CEN (~req_i[0]),
        .GWEN(~we_i[0]),
        .WEN (wen_n),
        .A   (addr_i[0]),
        .D   (wdata_i[0]),
        .EMA (3'b000),
        .RETN(1'b1)
      );
    end else begin : gen_rf_16xk128
      for (genvar t = 0; t < RfTiles; t++) begin : gen_tile
        qc_rf_16x128m1 i_macro (
          .Q   (q[t*128+:128]),
          .CLK (clk_i),
          .CEN (~req_i[0]),
          .WEN (~we_i[0]),
          .A   (addr_i[0]),
          .D   (wdata_i[0][t*128+:128]),
          .EMA (3'b000),
          .RETN(1'b1)
        );
      end
`ifndef SYNTHESIS
      always @(posedge clk_i) begin
        if (req_i[0] && we_i[0] && !(&be_i[0]))
          $error("%m: partial write (be_i=%h) on a register-file macro without write mask", be_i[0]);
      end
`endif
    end

    tc_sram_qc_hold #(
      .DataWidth(DataWidth)
    ) i_hold (
      .clk_i,
      .rst_ni,
      .req_i  (req_i[0]),
      .we_i   (we_i[0]),
      .q_i    (q),
      .rdata_o(rdata_o[0])
    );

  end else begin : gen_flops
    tc_sram_qc_ff #(
      .NumWords (NumWords),
      .DataWidth(DataWidth),
      .ByteWidth(ByteWidth),
      .NumPorts (NumPorts),
      .Latency  (Latency)
    ) i_ff (
      .clk_i,
      .rst_ni,
      .req_i,
      .we_i,
      .addr_i,
      .wdata_i,
      .be_i,
      .rdata_o
    );
  end

`ifndef SYNTHESIS
  initial begin
    if (PrintSimCfg) begin
      $display("%m: tc_sram tsmc65 %0d x %0d bit, %0d port(s): %s", NumWords, DataWidth, NumPorts,
               IsTcdm ? "qc_sp_1024x64m8" : IsRf16 ? "qc_rf_16x128m1 tiles" : "flip-flops");
    end
  end
`endif

endmodule


// Keeps the tc_sram read-data contract on a write-through macro: rdata_o = last read data, stable over writes.
module tc_sram_qc_hold #(
  parameter int unsigned DataWidth = 64
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic                 req_i,
  input  logic                 we_i,
  input  logic [DataWidth-1:0] q_i,
  output logic [DataWidth-1:0] rdata_o
);
  logic                 rd_last_q;   // the last access was a read: the macro output holds its data
  logic [DataWidth-1:0] hold_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_last_q <= 1'b0;
    end else if (req_i) begin
      rd_last_q <= ~we_i;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      hold_q <= '0;
    end else if (req_i && we_i && rd_last_q) begin
      hold_q <= q_i;
    end
  end

  assign rdata_o = rd_last_q ? q_i : hold_q;
endmodule


// Flip-flop memory with the tc_sram behaviour (Latency 1): byte-enabled writes, registered read data that is
// updated by reads only.  Used for shapes without a macro.
module tc_sram_qc_ff #(
  parameter int unsigned NumWords  = 16,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned ByteWidth = 8,
  parameter int unsigned NumPorts  = 1,
  parameter int unsigned Latency   = 1,
  // derived
  parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth   = (DataWidth + ByteWidth - 32'd1) / ByteWidth
) (
  input  logic                                clk_i,
  input  logic                                rst_ni,
  input  logic [NumPorts-1:0]                 req_i,
  input  logic [NumPorts-1:0]                 we_i,
  input  logic [NumPorts-1:0][AddrWidth-1:0]  addr_i,
  input  logic [NumPorts-1:0][DataWidth-1:0]  wdata_i,
  input  logic [NumPorts-1:0][BeWidth-1:0]    be_i,
  output logic [NumPorts-1:0][DataWidth-1:0]  rdata_o
);
  logic [NumWords-1:0][DataWidth-1:0] mem_q;

  // writes: the highest port wins on an address conflict (the generic model leaves this undefined)
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mem_q <= '0;
    end else begin
      for (int p = 0; p < NumPorts; p++) begin
        if (req_i[p] && we_i[p] && addr_i[p] < NumWords) begin
          for (int b = 0; b < DataWidth; b++) begin
            if (be_i[p][b / ByteWidth]) mem_q[addr_i[p]][b] <= wdata_i[p][b];
          end
        end
      end
    end
  end

  for (genvar p = 0; p < NumPorts; p++) begin : gen_rd
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        rdata_o[p] <= '0;
      end else if (req_i[p] && !we_i[p]) begin
        rdata_o[p] <= mem_q[addr_i[p]];
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (Latency != 1) $fatal(1, "%m: tc_sram (tsmc65 flip-flop model) supports Latency 1 only, got %0d", Latency);
  end
`endif
endmodule
