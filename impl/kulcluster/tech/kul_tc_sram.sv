// TSMC 65 nm (tcbn65gplus) implementation of the KUL cluster's `KULCluster_tc_sram` (same parameters / ports as the
// generic cell in hw/kulcluster/generated/kulcluster_syn.sv, which gen_src.sh strips from the synthesis pickle).
//
// Each port maps to compiled ARM register-file macros (impl/kulcluster/macros.txt, flow/tsmc65/sram/mc_gen.sh):
//   NumWords 512, DataWidth 64, ByteWidth 8 -> kul_rf_512x64m4 (byte write mask)          TCDM bank (32x)
//   NumWords 128, DataWidth k*128           -> k x kul_rf_128x128m1 side by side           icache data way (2 x 2)
//   NumWords 128, DataWidth <= 40           -> kul_rf_128x40m1, unused MSBs tied to 0      icache tag way (2x)
//   anything else                           -> flip-flop array (KULCluster_tc_sram_qc_ff)
// Only NumPorts = 1, Latency = 1 shapes use macros.  The icache macros have no write mask; their callers always
// write whole words (be_i = '1).
//
// Macro pins: CEN / WEN active low (the masked RF has one WEN per byte and no global write enable: a write with
// be_i = 0 is a read inside the macro, which the hold adapter hides), EMA tied to 000, RETN inactive (1).
// The read-data contract of tc_sram (rdata_o stable over writes) is kept by KULCluster_tc_sram_qc_hold, a
// prefixed copy of tc_sram_qc_hold of hw/tech/tsmc65/tc_sram.sv (gen_src.sh).
module KULCluster_tc_sram #(
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
  localparam bit IsTcdm   = OnePort && NumWords == 512 && DataWidth == 64 && ByteWidth == 8;
  localparam bit IsIcData = OnePort && NumWords == 128 && DataWidth % 128 == 0;
  localparam bit IsIcTag  = OnePort && NumWords == 128 && DataWidth <= 40 && DataWidth > 20;
  localparam int RfTiles  = DataWidth / 128;

  if (IsTcdm || IsIcData || IsIcTag) begin : gen_macro
    data_t q;      // macro read data (write-through)

    if (IsTcdm) begin : gen_rf_512x64
      logic [7:0] wen_n;
      for (genvar b = 0; b < 8; b++) begin : gen_wen
        assign wen_n[b] = ~(we_i[0] & be_i[0][b]);
      end
      kul_rf_512x64m4 i_macro (
        .Q   (q),
        .CLK (clk_i),
        .CEN (~req_i[0]),
        .WEN (wen_n),
        .A   (addr_i[0]),
        .D   (wdata_i[0]),
        .EMA (3'b000),
        .RETN(1'b1)
      );
    end else if (IsIcData) begin : gen_rf_128xk128
      for (genvar t = 0; t < RfTiles; t++) begin : gen_tile
        kul_rf_128x128m1 i_macro (
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
    end else begin : gen_rf_128x40
      logic [39:0] q40, d40;
      assign d40 = 40'(wdata_i[0]);
      assign q   = q40[DataWidth-1:0];
      kul_rf_128x40m1 i_macro (
        .Q   (q40),
        .CLK (clk_i),
        .CEN (~req_i[0]),
        .WEN (~we_i[0]),
        .A   (addr_i[0]),
        .D   (d40),
        .EMA (3'b000),
        .RETN(1'b1)
      );
    end
`ifndef SYNTHESIS
    if (!IsTcdm) begin : gen_chk
      always @(posedge clk_i) begin
        if (req_i[0] && we_i[0] && !(&be_i[0]))
          $error("%m: partial write (be_i=%h) on a register-file macro without write mask", be_i[0]);
      end
    end
`endif

    KULCluster_tc_sram_qc_hold #(
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
    KULCluster_tc_sram_qc_ff #(
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
      $display("%m: KUL tc_sram tsmc65 %0d x %0d bit, %0d port(s): %s", NumWords, DataWidth, NumPorts,
               IsTcdm ? "kul_rf_512x64m4" : IsIcData ? "kul_rf_128x128m1 tiles" : IsIcTag ? "kul_rf_128x40m1" :
               "flip-flops");
    end
  end
`endif

endmodule
