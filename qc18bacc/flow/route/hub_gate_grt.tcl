# Gate GRT of the placed hub (blocks/hub/run.sh gate; results/r10b.md, r15.md, r22.md): global route of db/place.odb in
# its own process, uniform adjustment 0.25 + the per-layer QB15_GADJ_L (route/gadj_layers.tcl), -allow_congestion with
# 10 congestion iterations; guide + congestion report into <run>/grt_pl/, GRT-parasitics timing line, db/grt_pl.odb.
# The congestion report is the routability check of the floorplan before the production steps.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
source $::QBF/route/gadj_layers.tcl
set ::STEPS {init floorplan pdn place cts route finish}
set_thread_count [qc_env QC_PNR_THREADS 8]
set ::t0 [clock milliseconds]
proc ts {m} { puts [format "R10B_T %7.1f s %s" [expr {([clock milliseconds] - $::t0) / 1000.0}] $m]; flush stdout }
qc_load place
ts loaded
set od $::OUT/grt_pl
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER 0.25
set a [list -guide_file $od/route.guide -congestion_iterations 10 -allow_congestion -verbose \
          -congestion_report_file $od/gr_congestion.rpt]
ts "global_route $a"
global_route {*}$a
ts "global_route done"
estimate_parasitics -global_routing
set _s [sta::worst_slack_corner [sta::find_corner tt] max]
set _p [get_property [get_clocks qb_clk] period]
puts [format "R10B grt tt setup_wns_ns %.3f fmax_est_mhz %.1f" [expr {$_s * 1e9}] [expr {1000.0 / ($_p - $_s * 1e9)}]]
ts "parasitics + sta done"
write_db $::OUT/db/grt_pl.odb
ts saved
exit
