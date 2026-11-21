# R39: fresh route.guide for db/<R39_DB [grt]>.odb (in a run dir via impl/r29/or29.sh <tag> regrt39.tcl <log>).
# Bug (impl/r35/shim/post_grt.tcl): the post-GRT repair (clones / buffers + incremental GRT) runs AFTER post_grt14.tcl
# wrote route.guide, so the guides miss the new instances -> DRT-0218 "Guide is not connected to design" (r39_w).
# Same GRT settings as the flow (route.tcl GR_ADJUST + QB15_GADJ_L, GR_ITER, -allow_congestion as r9b); db not written.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 16]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R39_DB grt]
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
foreach {l a} [qc_env QB15_GADJ_L "M2-M3 0.6"] { set_global_routing_layer_adjustment $l $a }
set t [clock seconds]
global_route -guide_file $::OUT/route.guide -congestion_iterations [p GR_ITER] -allow_congestion \
    -congestion_report_file $::OUT/rpt/gr_congestion_r39.rpt
puts "R39_REGRT done [expr {[clock seconds] - $t}] s"
