# PRE_CTS_TCL of impl/r6c/chip.cfg: impl/r6b/cts_pre.tcl (spread procedures when restarting at cts), QB_SPREAD3
# override, then QB_ICG (icg.tcl) on the placed design before clock_tree_synthesis.
source $::QB_R6B/cts_pre.tcl
if {[qb_env QB_SPREAD3 0] && [info commands qb6c_spread3] eq ""} { source $::QB_R6C/spread3.tcl }
if {[qb_env QB_ICG 0]} { source $::QB_R6C/icg.tcl; qb6c_icg }
source $::QB_R6C/est_rc.tcl
