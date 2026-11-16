# GRT probe of a placed qb_act2_blk checkpoint (results/r7c.md): global route with -allow_congestion and few
# congestion iterations (QB7_GR_ITER, default 10) to measure routing demand / overflow per layer in minutes, then
# timing at global-route parasitics.  Env: QB7_RUN (run dir), QB7_DB (checkpoint, default cts_rt).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QB7_RUN)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_read_liberty
read_db $::OUT/db/[qc_env QB7_DB cts_rt].odb
set_dont_use $::QC_PNR_DONT_USE
read_sdc $::OUT/db/cts.sdc
qc_set_rc
set_propagated_clock [all_clocks]
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
set t [clock seconds]
global_route -allow_congestion -congestion_iterations [qc_env QB7_GR_ITER 10] -congestion_report_file $::OUT/rpt/grt_probe_congestion.rpt -verbose
puts "QB7_GRT_PROBE grt_s [expr {[clock seconds] - $t}]"
estimate_parasitics -global_routing
puts "QB7_GRT_PROBE [qc_util]"
report_wns
report_tns
report_checks -path_delay max -fields {cap slew} -digits 3 > $::OUT/rpt/grt_probe_setup.rpt
exit
