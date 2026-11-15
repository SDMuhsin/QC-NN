# impl/r5b: DRV repair after CTS (results/r5b.md section 4): the place step's legalisation (detailed placement,
# max displacement 1000 um, measured max 1 583 um) moved cells after the DRV repair and left long nets on D0 / D1
# drivers (slews up to 3.9 ns).  Loads db/cts.odb, propagated clock, qc_repair_drv (violating nets only),
# detailed placement (QB_DPL2 displacement, default {200 200}), saves db/cts_drv.odb (+ .sdc).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 1]
set ::STEPS {init floorplan pdn place cts route finish}
set ::T0 [clock seconds]
qc_load cts
set_propagated_clock [all_clocks]
estimate_parasitics -placement
set n [expr {[sta::max_slew_violation_count] + [sta::max_capacitance_violation_count] + [sta::max_fanout_violation_count]}]
qc_log "cts_drv: drv violations before $n"
qc_repair_drv
set dpl [qc_env QB_DPL2 {200 200}]
if {[catch {detailed_placement -max_displacement $dpl} e]} { qc_log "cts_drv: detailed placement failed: $e" }
estimate_parasitics -placement
set n [expr {[sta::max_slew_violation_count] + [sta::max_capacitance_violation_count] + [sta::max_fanout_violation_count]}]
qc_log "cts_drv: drv violations after $n [qc_util]"
qc_summary "cts_drv [qc_util]"
qc_summary "cts_drv [join [qc_timing_lines cts_drv] { | }]"
qc_save cts_drv
exit
