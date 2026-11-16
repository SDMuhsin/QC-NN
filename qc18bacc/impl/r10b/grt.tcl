# R10b GRT-only run from a checkpoint (run.sh grt): QB_DB [cts] of run QC_PNR_OUT, routing layers / adjustment as
# flow route.tcl (QB_GADJ [0.25]), global_route -allow_congestion with QB_GI [3] congestion iterations (+ QB_GARGS),
# guide + congestion report into QB_GOUT, GRT parasitics timing line, checkpoint db/grt_<QB_GTAG>.odb.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set_thread_count [qc_env QC_PNR_THREADS 8]
set ::t0 [clock milliseconds]
proc ts {m} { puts [format "R10B_T %7.1f s %s" [expr {([clock milliseconds] - $::t0) / 1000.0}] $m]; flush stdout }
qc_load [qc_env QB_DB cts]
ts loaded
set od [qc_env QB_GOUT $::OUT]
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [qc_env QB_GADJ 0.25]
set a [list -guide_file $od/route.guide -congestion_iterations [qc_env QB_GI 3] -allow_congestion -verbose \
          -congestion_report_file $od/gr_congestion.rpt {*}[qc_env QB_GARGS]]
ts "global_route $a"
global_route {*}$a
ts "global_route done"
estimate_parasitics -global_routing
set _s [sta::worst_slack_corner [sta::find_corner tt] max]
set _p [get_property [get_clocks qb_clk] period]
puts [format "R10B grt tt setup_wns_ns %.3f fmax_est_mhz %.1f" [expr {$_s * 1e9}] [expr {1000.0 / ($_p - $_s * 1e9)}]]
ts "parasitics + sta done"
write_db $::OUT/db/grt_[qc_env QB_GTAG a].odb
ts saved
exit
