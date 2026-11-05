// Synthesis top of chimera's open Snitch cluster (CONVOLVE-TO), as chimera instantiates it.
//
// One `chimera_cluster` (hw/chimera_cluster.sv: snitch_cluster with chimera's parameters plus the narrow and
// cluster AXI adapters) with chimera's SoC configuration ChimeraCfg[0] and the AXI types of chimera_top_wrapper.
// The cluster slot (ClusterSlot) picks the core count, hart base id and cluster base address the way
// chimera_clu_domain does; the default slot 4 is the 9-core cluster (8 compute cores + 1 DMA core), the chimera_cluster
// default.  Slots 0..3 are the 2-core clusters.
//
// Two clocks as in chimera: soc_clk_i (SoC-side AXI ports) and clu_clk_i (cluster), crossed by axi_cdc in the
// cluster adapter.  hart_base_id_i / cluster_base_addr_i are the constants chimera_clu_domain ties; boot address,
// interrupts, debug requests and the wide-memory bypass are top-level inputs.
module qc_snitch_cluster_top
  import cheshire_pkg::*;
  import chimera_pkg::*;
#(
  parameter int unsigned ClusterSlot = ETHCLUSTERIDX,
  // derived, do not override
  parameter int unsigned NrCores     = ChimeraClusterCfg.NrCores[ClusterSlot]
) (
  input  logic                         soc_clk_i,
  input  logic                         clu_clk_i,
  input  logic                         rst_ni,
  input  logic                         widemem_bypass_i,
  input  logic [                 31:0] boot_addr_i,
  input  logic [          NrCores-1:0] debug_req_i,
  input  logic [          NrCores-1:0] meip_i,
  input  logic [          NrCores-1:0] mtip_i,
  input  logic [          NrCores-1:0] msip_i,
  // narrow AXI: SoC -> cluster (slave), cluster -> SoC (2 masters)
  input  qc_chimera_types::axi_slv_req_t         narrow_in_req_i,
  output qc_chimera_types::axi_slv_rsp_t         narrow_in_resp_o,
  output qc_chimera_types::axi_mst_req_t   [1:0] narrow_out_req_o,
  input  qc_chimera_types::axi_mst_rsp_t   [1:0] narrow_out_resp_i,
  // wide AXI: cluster DMA -> memory island
  output qc_chimera_types::axi_wide_mst_req_t    wide_out_req_o,
  input  qc_chimera_types::axi_wide_mst_rsp_t    wide_out_resp_i
);

  localparam chimera_cfg_t Cfg = ChimeraCfg[0];

  chimera_cluster #(
    .Cfg              (Cfg),
    .NrCores          (NrCores),
    .narrow_in_req_t  (qc_chimera_types::axi_slv_req_t),
    .narrow_in_resp_t (qc_chimera_types::axi_slv_rsp_t),
    .narrow_out_req_t (qc_chimera_types::axi_mst_req_t),
    .narrow_out_resp_t(qc_chimera_types::axi_mst_rsp_t),
    .wide_out_req_t   (qc_chimera_types::axi_wide_mst_req_t),
    .wide_out_resp_t  (qc_chimera_types::axi_wide_mst_rsp_t)
  ) i_cluster (
    .soc_clk_i          (soc_clk_i),
    .clu_clk_i          (clu_clk_i),
    .rst_ni             (rst_ni),
    .widemem_bypass_i   (widemem_bypass_i),
    .debug_req_i        (debug_req_i),
    .meip_i             (meip_i),
    .mtip_i             (mtip_i),
    .msip_i             (msip_i),
    .hart_base_id_i     (10'(_sumVector(ChimeraClusterCfg.NrCores, ClusterSlot) + 1)),
    .cluster_base_addr_i(Cfg.ChsCfg.AxiExtRegionStart[ClusterSlot][Cfg.ChsCfg.AddrWidth-1:0]),
    .boot_addr_i        (boot_addr_i),
    .narrow_in_req_i    (narrow_in_req_i),
    .narrow_in_resp_o   (narrow_in_resp_o),
    .narrow_out_req_o   (narrow_out_req_o),
    .narrow_out_resp_i  (narrow_out_resp_i),
    .wide_out_req_o     (wide_out_req_o),
    .wide_out_resp_i    (wide_out_resp_i)
  );

endmodule
