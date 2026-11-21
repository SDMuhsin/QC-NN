# PRE_ROUTE_TCL of impl/r14/top14.cfg: clock balancing (bal14.tcl, QB14_BAL 1), then impl/r9b/route_pre.tcl
# (QB_POSTCTS 0: no post-CTS repair; GRT -allow_congestion).
if {[qb_env QB14_BAL 1]} { source $::QB_R14/bal14.tcl }
# R43 opt-in QB43_AUTOL 1: chip IO latency = measured top-flop clock median after balancing (impl/r43/autol43_or.tcl)
if {[qb_env QB43_AUTOL 0]} { source [file normalize $::QB_R14/../r43/autol43_or.tcl]; if {[info commands q14_measure] eq ""} { source $::QB_R14/clk14.tcl }; q43_autol post_cts }
source $::QB_R9B/route_pre.tcl
