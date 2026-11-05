# Timing repair after CTS (PRE_ROUTE_TCL; the cts step runs with REPAIR_TIMING 0).  As cts.tcl, but hold repair
# without extra margin and legalisation with a larger search window: most hold buffers sit at the TCDM macro D pins
# (ff, -0.03 ns), 23 um inside macro + halo, and the default detailed_placement window leaves ~2000 of them unplaced.
estimate_parasitics -placement
repair_timing -setup -setup_margin [p SETUP_MARGIN] -max_utilization [p MAX_UTIL]
repair_timing -hold -hold_margin [p KUL_HOLD_MARGIN 0.0] -max_utilization [p MAX_UTIL]
detailed_placement -max_displacement {300 300}
check_placement
estimate_parasitics -placement
qc_to $::OUT/rpt/cts_opt.skew.rpt { report_clock_skew }
qc_report cts_opt
qc_summary "cts_opt [qc_util]"
qc_summary "cts_opt [join [qc_timing_lines cts_opt] { | }]"
