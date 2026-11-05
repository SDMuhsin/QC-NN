// TSMC 65 nm `tc_sram_impl` (same parameters and ports as tech_cells_generic): wraps this overlay's tc_sram.
// impl_i is ignored (the macros' margin inputs are tied in tc_sram), impl_o is driven with ImplOutSim.
module tc_sram_impl #(
  parameter int unsigned NumWords     = 32'd1024,
  parameter int unsigned DataWidth    = 32'd128,
  parameter int unsigned ByteWidth    = 32'd8,
  parameter int unsigned NumPorts     = 32'd2,
  parameter int unsigned Latency      = 32'd1,
  parameter              SimInit      = "none",
  parameter bit          PrintSimCfg  = 1'b0,
  parameter              ImplKey      = "none",
  parameter type         impl_in_t    = logic,
  parameter type         impl_out_t   = logic,
  parameter impl_out_t   ImplOutSim   = 'X,
  // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
  parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth   = (DataWidth + ByteWidth - 32'd1) / ByteWidth,
  parameter type         addr_t    = logic [AddrWidth-1:0],
  parameter type         data_t    = logic [DataWidth-1:0],
  parameter type         be_t      = logic [BeWidth-1:0]
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  impl_in_t             impl_i,
  output impl_out_t            impl_o,
  input  logic  [NumPorts-1:0] req_i,
  input  logic  [NumPorts-1:0] we_i,
  input  addr_t [NumPorts-1:0] addr_i,
  input  data_t [NumPorts-1:0] wdata_i,
  input  be_t   [NumPorts-1:0] be_i,
  output data_t [NumPorts-1:0] rdata_o
);
  assign impl_o = ImplOutSim;

  tc_sram #(
    .NumWords   (NumWords),
    .DataWidth  (DataWidth),
    .ByteWidth  (ByteWidth),
    .NumPorts   (NumPorts),
    .Latency    (Latency),
    .SimInit    (SimInit),
    .PrintSimCfg(PrintSimCfg),
    .ImplKey    (ImplKey)
  ) i_tc_sram (
    .clk_i,
    .rst_ni,
    .req_i,
    .we_i,
    .addr_i,
    .wdata_i,
    .be_i,
    .rdata_o
  );
endmodule
