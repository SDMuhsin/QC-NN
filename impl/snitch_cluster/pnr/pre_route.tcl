# Timing repair after CTS (PRE_ROUTE_TCL, start of the route step; cts.tcl runs with REPAIR_TIMING 0): setup with
# a bounded TNS effort (repair_tns SN_REPAIR_TNS percent of the violating endpoints, default 0 = worst paths only:
# pre-CTS the design has ~-12 ns WNS / -388k ns TNS at ss, long nets on DC's D0 / D1 drivers, and a full TNS repair
# of 1.4M instances does not fit the run-time budget), then hold (all corners, HOLD_MARGIN), legalisation.
# SN_SETUP_REPAIR=0 skips the setup repair.  Writes its own checkpoint db/cts_opt.odb.
set tns [qc_env SN_REPAIR_TNS 0]
if {[qc_env SN_SETUP_REPAIR 1]} {
    qc_log "pre_route: repair_timing -setup (repair_tns $tns)"
    repair_timing -setup -setup_margin [p SETUP_MARGIN] -repair_tns $tns -max_utilization [p MAX_UTIL]
}
qc_log "pre_route: repair_timing -hold"
repair_timing -hold -hold_margin [p HOLD_MARGIN] -max_utilization [p MAX_UTIL]
detailed_placement
check_placement
estimate_parasitics -placement
qc_report cts_opt
qc_summary "cts_opt [qc_util]"
qc_summary "cts_opt [join [qc_timing_lines cts_opt] { | }]"
qc_save cts_opt
source [file dirname [p PRE_ROUTE_TCL]]/route_guard.tcl
