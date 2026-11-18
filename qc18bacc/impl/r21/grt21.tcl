# R21 GRT of a route input checkpoint for a detailed route (run.sh grt; the M5 control): as impl/r10b/grt.tcl
# (QB_DB [cts_rt], uniform QB_GADJ [0.25] + per-layer QB15_GADJ_L, QB_GI congestion iterations, -allow_congestion) plus the
# production post-GRT steps of impl/r21/post_grt.tcl (antenna repair QB21_ANT [3], guides rewritten), guides and
# congestion report into the run dir, checkpoint db/grt.odb + .sdc (what impl/r8/dr.tcl loads).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set_thread_count [qc_env QC_PNR_THREADS 8]
set ::T0 [clock seconds]
qc_load [qc_env QB_DB cts_rt]
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [qc_env QB_GADJ 0.25]
foreach {l a} [qc_env QB15_GADJ_L] { set_global_routing_layer_adjustment $l $a; qc_log "r21 grt: gadj $l $a" }
global_route -guide_file $::OUT/route.guide -congestion_iterations [qc_env QB_GI 10] -allow_congestion -verbose \
    -congestion_report_file $::OUT/rpt/gr_congestion.rpt
qc_log "r21 grt: global_route done ([expr {[clock seconds] - $::T0}] s)"
estimate_parasitics -global_routing
if {[qc_env QB21_ANT 3] > 0} {
    repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations [qc_env QB21_ANT 3]
    write_guides $::OUT/route.guide
    qc_log "r21 grt: repair_antennas done, guides rewritten ([expr {[clock seconds] - $::T0}] s)"
}
set _s [sta::worst_slack_corner [sta::find_corner tt] max]
set _p [get_property [get_clocks qb_clk] period]
qc_summary [format "r21 grt tt setup_wns_ns %.3f fmax_est_mhz %.1f" [expr {$_s * 1e9}] [expr {1000.0 / ($_p - $_s * 1e9)}]]
qc_save grt
exit
