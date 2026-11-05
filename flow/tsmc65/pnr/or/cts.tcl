# cts: clock tree (site buffers), propagated clocks, timing repair (setup, then hold) at placement parasitics.
if {[p PRE_CTS_TCL] ne ""} { source [p PRE_CTS_TCL] }
clock_tree_synthesis -buf_list $::QC_PNR_CTS_BUF -root_buf $::QC_PNR_CTS_ROOT -sink_clustering_enable \
    -sink_clustering_size [p CTS_CLUSTER_SIZE] -sink_clustering_max_diameter [p CTS_CLUSTER_DIAMETER] {*}[p CTS_ARGS]
set_propagated_clock [all_clocks]
repair_clock_nets
detailed_placement
estimate_parasitics -placement
if {[p REPAIR_TIMING]} {
    repair_timing -setup -setup_margin [p SETUP_MARGIN] -max_utilization [p MAX_UTIL]
    repair_timing -hold  -hold_margin [p HOLD_MARGIN] -max_utilization [p MAX_UTIL]
    detailed_placement
}
check_placement
estimate_parasitics -placement
qc_to $::OUT/rpt/cts.skew.rpt { report_clock_skew }
qc_report cts
qc_summary "cts [qc_util]"
qc_summary "cts [join [qc_timing_lines cts] { | }]"
