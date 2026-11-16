# POST_GRT_TCL of impl/r11/top.cfg (QB_GRT_STOP 1): impl/r9b/post_grt.tcl report + checkpoint + per-class timing
# (impl/r11/classes.tcl) at GRT parasitics; congestion report kept in rpt/gr_congestion.rpt by the flow.
if {[file exists $::QB_R11/classes.tcl]} { catch { source $::QB_R11/classes.tcl } _e; qc_log "r11 classes: $_e" }
source $::QB_R9B/post_grt.tcl
