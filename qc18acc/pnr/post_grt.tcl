# Post-global-route optimisation (POST_GRT_TCL of route.tcl; as impl/kulcluster/pnr): setup then hold repair with global-route parasitics,
# legalisation, incremental global route of the changed nets.
global_route -start_incremental
repair_timing -setup -setup_margin [p SETUP_MARGIN] -max_utilization [p MAX_UTIL] {*}[p QA_RT_ARGS {}]
repair_timing -hold -hold_margin [p HOLD_MARGIN] -max_utilization [p MAX_UTIL]
detailed_placement -max_displacement {300 300}
check_placement
global_route -end_incremental -congestion_report_file $::OUT/rpt/gr_congestion_incr.rpt
estimate_parasitics -global_routing
qc_report grt_opt
qc_summary "grt_opt [qc_util]"
qc_summary "grt_opt [join [qc_timing_lines grt_opt] { | }]"
