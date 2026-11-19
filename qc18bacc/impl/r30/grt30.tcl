# R30 probe (no db written): global_route -verbose of a run's db (R30_DB [cts_rt]) with the production settings
# (layers, GR_ADJUST, QB15_GADJ_L, QB9_GR_ITER), to see GRT's per-layer capacity / usage / overflow.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R30_DB cts_rt]
set_thread_count 16
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
foreach {l a} [qc_env QB15_GADJ_L "M5-M9 0.10"] { set_global_routing_layer_adjustment $l $a }
foreach {l a} [qc_env R30_GADJ ""] { set_global_routing_layer_adjustment $l $a; puts "R30G gadj $l $a" }
puts "R30G layers $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER adj [p GR_ADJUST] iters [qc_env QB9_GR_ITER 10]"
global_route -congestion_iterations [qc_env QB9_GR_ITER 10] -allow_congestion -verbose
exit
