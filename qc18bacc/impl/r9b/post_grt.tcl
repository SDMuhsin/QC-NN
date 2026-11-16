# POST_GRT_TCL of impl/r9b/hub.cfg (QB_GRT_STOP 1): timing at global-route parasitics, checkpoint db/grt.odb, exit
# (detailed route in a fresh process: run.sh dr).
qc_to $::OUT/rpt/grt_setup.rpt { report_checks -path_delay max -format full_clock_expanded -fields {input_pins slew cap fanout} -digits 3 -group_count 20 -endpoint_count 1 }
qc_to $::OUT/rpt/grt_hold.rpt { report_checks -path_delay min -digits 3 -group_count 5 }
set _s [sta::worst_slack_corner [sta::find_corner tt] max]
set _p [get_property [get_clocks qb_clk] period]
qc_summary [format "r9b grt tt setup_wns_ns %.3f fmax_est_mhz %.1f" [expr {$_s * 1e9}] [expr {1000.0 / ($_p - $_s * 1e9)}]]
qc_save grt
qc_log "r9b: stop after global route (QB_GRT_STOP)"
exit
