// AXI types of chimera's SoC configuration ChimeraCfg[0], exactly as chimera_top_wrapper derives them
// (cheshire AXI types plus the memory-island wide types), for the ports of qc_snitch_cluster_top.
`include "cheshire/typedef.svh"
`include "chimera/typedef.svh"

package qc_chimera_types;
  import cheshire_pkg::*;
  import chimera_pkg::*;

  localparam chimera_cfg_t  Cfg    = ChimeraCfg[0];
  localparam cheshire_cfg_t ChsCfg = Cfg.ChsCfg;

  `CHESHIRE_TYPEDEF_ALL(, ChsCfg)
  `CHIMERA_TYPEDEF_ALL(, Cfg)

  typedef mem_isl_wide_axi_mst_req_t axi_wide_mst_req_t;
  typedef mem_isl_wide_axi_mst_rsp_t axi_wide_mst_rsp_t;
endpackage
