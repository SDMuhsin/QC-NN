# R9a route from the post-CTS-repair checkpoint db/cts_rt.odb (results/r9a.md): the flow's route step (or/route.tcl)
# without the repair (done) and with global_route -allow_congestion -congestion_iterations QB9_GR_ITER (default 20):
# the flow's GRT (50 iterations, no overflow allowed) spent > 1 h in maze rerouting on S1 / pre-mux hotspots (r9a_f2r);
# the remaining local overflow is left to the detailed router.  Then antenna repair, fillers, DR (DR_END_ITER), antenna
# check, db/route_dr.odb.  QB9_GR_ADJ: GRT layer adjustment (default the cfg's 0.25); QB9_ANT 0: no GRT antenna repair
# (it segfaults on nets with missing global routes, r9a_f2d); and the finish step (DEF, netlists, conn dump).  Env QB9_RUN = run dir with config.tcl + db/.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QB9_RUN)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set ::T0 [clock seconds]
qc_read_liberty
read_db $::OUT/db/cts_rt.odb
set_dont_use $::QC_PNR_DONT_USE
read_sdc $::OUT/db/cts.sdc
qc_set_rc
set_propagated_clock [all_clocks]
set_thread_count [qc_env QC_PNR_THREADS 8]
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [qc_env QB9_GR_ADJ [p GR_ADJUST]]
qc_log "r9a GR adjustment [qc_env QB9_GR_ADJ [p GR_ADJUST]]"
# R35 opt-in: per-layer adjustment pairs QB15_GADJ_L (e.g. "M2-M3 0.6", R30 fix) after the uniform one (unset = as before)
foreach {_l _a} [qc_env QB15_GADJ_L ""] { set_global_routing_layer_adjustment $_l $_a; qc_log "r35 gadj $_l $_a" }
set t [clock seconds]
global_route -guide_file $::OUT/route.guide -allow_congestion -congestion_iterations [qc_env QB9_GR_ITER 20] \
    -congestion_report_file $::OUT/rpt/gr_congestion.rpt -verbose
qc_summary "r9a grt_s [expr {[clock seconds] - $t}]"
estimate_parasitics -global_routing
qc_summary "groute [join [qc_timing_lines groute] { | }]"
if {[qc_env QB9_ANT 1] && [p ANTENNA_ITER] > 0} { repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations [p ANTENNA_ITER] }
set fill {}
if {[p DCAP]} { set fill [concat $fill $::QC_PNR_DCAP] }
if {[p FILL]} { set fill [concat $fill $::QC_PNR_FILL] }
if {[llength $fill]} { filler_placement $fill }
check_placement
set t [clock seconds]
detailed_route -output_drc $::OUT/rpt/drt.drc.rpt -output_maze $::OUT/drt_maze.log \
    -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
    -droute_end_iter [p DR_END_ITER] -verbose 1 {*}[p DR_ARGS]
qc_summary "r9a drt_s [expr {[clock seconds] - $t}]"
qc_save route_dr
check_antennas -verbose
source $::env(QC_FLOW)/pnr/or/finish.tcl
qc_save finish
