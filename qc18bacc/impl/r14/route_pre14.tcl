# PRE_ROUTE_TCL of impl/r14/top14.cfg: clock balancing (bal14.tcl, QB14_BAL 1), then impl/r9b/route_pre.tcl
# (QB_POSTCTS 0: no post-CTS repair; GRT -allow_congestion).
if {[qb_env QB14_BAL 1]} { source $::QB_R14/bal14.tcl }
source $::QB_R9B/route_pre.tcl
