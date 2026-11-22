# R46 minimal repro of the r43_a repair_antennas SEGFAULT (results/r46.md): db R46_DB [grt] only (no liberty / SDC:
# the antenna wire build needs none), the flow's GRT settings as impl/r43/hold43.tcl, then impl/r43/ant43.tcl q43_ant.
# Run in a run dir via impl/r29/or29.sh <tag> ant46.tcl <log>.  R46_NETS <file>: before the repair, print every net
# whose GRT route has a segment the wire builder cannot encode (impl/r46/seg46.tcl).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 16]
proc qb_env {n d} { return [expr {[info exists ::env($n)] ? $::env($n) : $d}] }
read_db $::OUT/db/[qc_env R46_DB grt].odb
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
foreach {l a} [qc_env QB15_GADJ_L "M2-M3 0.6"] { set_global_routing_layer_adjustment $l $a }
global_route -congestion_iterations [p GR_ITER] -allow_congestion
qc_log "r46 ant46: global_route done, min/max layer $::QC_PNR_MIN_LAYER $::QC_PNR_MAX_LAYER"
source $::env(QC_FLOW)/../../qc18bacc/impl/r43/ant43.tcl
q43_ant
qc_log "r46 ant46 done"
