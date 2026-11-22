# qc18bacc flow: Tcl helpers shared by every block config, hook and standalone OpenROAD script.
#   ::QBF       root of the qc18bacc flow (qc18bacc/flow), from QC_FLOW (flow/tsmc65, set by flow/tsmc65 common/tool.sh)
#   qb_env n d  environment variable n if it exists (even when empty), else d
set ::QBF [file normalize $::env(QC_FLOW)/../../qc18bacc/flow]
proc qb_env {n d} { return [expr {[info exists ::env($n)] ? $::env($n) : $d}] }
