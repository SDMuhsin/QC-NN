// Primary DUT: snitch_cluster with sim/cfg/chimera_fp.hjson (chimera's cluster + upstream FP compute cores) on
// TSMC 65 nm: tech overlay, snitch_cluster sources of the sim workspace (bender), clustergen wrapper (top
// snitch_cluster_wrapper).
-f ../../hw/tech/tsmc65/tsmc65.f
-f flist/fp.f
