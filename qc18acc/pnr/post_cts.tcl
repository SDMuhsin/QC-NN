# Timing repair after CTS (PRE_ROUTE_TCL; the cts step runs with REPAIR_TIMING 0): setup, then hold without extra
# margin, legalisation with a larger window (hold buffers near the macro pins sit next to macro + halo).
# Optional settings (all default off = the v2 recipe of results/pnr.md):
#   P(QA_IO_REF) 1       host-port IO delays relative to the propagated clock (io_ref.tcl)
#   P(QA_RT_FOCUS) 1     one setup repair pass without the macro / IO paths first (rt_focus.tcl)
#   P(QA_RT_ARGS)        extra repair_timing -setup options (also in post_grt.tcl)
#   P(QA_MACRO_HOLD) ns  extra hold margin at the macro CLK pins (macro_hold.tcl, also in post_grt.tcl)
if {[p QA_IO_REF 0]} { source [file dirname [p PIN_TCL]]/io_ref.tcl }
estimate_parasitics -placement
if {[p QA_RT_FOCUS 0]} { source [file dirname [p PIN_TCL]]/rt_focus.tcl }
repair_timing -setup -setup_margin [p SETUP_MARGIN] -max_utilization [p MAX_UTIL] {*}[p QA_RT_ARGS {}]
if {[p QA_MACRO_HOLD 0] > 0} { source [file dirname [p PIN_TCL]]/macro_hold.tcl }
repair_timing -hold -hold_margin [p QA_HOLD_MARGIN 0.0] -max_utilization [p MAX_UTIL]
detailed_placement -max_displacement {300 300}
check_placement
estimate_parasitics -placement
qc_to $::OUT/rpt/cts_opt.skew.rpt { report_clock_skew }
qc_report cts_opt
qc_summary "cts_opt [qc_util]"
qc_summary "cts_opt [join [qc_timing_lines cts_opt] { | }]"
