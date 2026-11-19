# R21 POST_GRT_TCL: antenna repair at global-route time (QB21_ANT iterations [3], diode $::QC_PNR_DIODE), guides
# rewritten after the repair, then impl/r9b/post_grt.tcl (GRT timing reports, checkpoint db/grt.odb, exit; DR in a
# fresh process: impl/r21/run.sh dr).
if {[qb_env QB21_ANT 3] > 0} {
    set t [clock seconds]
    # opt-in R28: QB28_ANT_MARGIN <pct> (repair_antennas -ratio_margin: GRT under-estimates the DR antenna ratios)
    set _m [expr {[qb_env QB28_ANT_MARGIN 0] > 0 ? [list -ratio_margin [qb_env QB28_ANT_MARGIN 0]] : {}}]
    repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations [qb_env QB21_ANT 3] {*}$_m
    write_guides $::OUT/route.guide
    qc_log "r21: repair_antennas [expr {[clock seconds] - $t}] s, guides rewritten"
}
qc_to $::OUT/rpt/grt_drv.rpt { report_check_types -max_slew -max_capacitance -max_fanout }
source $::QB_R9B/post_grt.tcl
