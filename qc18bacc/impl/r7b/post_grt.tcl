# POST_GRT_TCL of impl/r7b/chip.cfg (QB_GRT_STOP 1): path classes at global-route parasitics (classes.tcl ->
# rpt/grt_classes.txt), then impl/r6c/post_grt.tcl (checkpoint db/grt.odb and exit)
source $::QB_R7B/classes.tcl
if {[catch {qb7_classes} e]} { qc_log "r7b: path classes failed: $e" }
source $::QB_R6C/post_grt.tcl
