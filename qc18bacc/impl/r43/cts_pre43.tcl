# R43 PRE_CTS_TCL of the chip top (QB14_CTS_PRE, results/r43.md; R44 gated-clock root cause, results/r44.md):
#   1. impl/r44/icgsplit44.tcl (QB44_SPLIT <gap_um>): ICGs whose sinks form two groups > gap apart are cloned BEFORE CTS
#   2. QB43_ICG [1]: impl/r6c/icg.tcl qb6c_icg - every CKLNQD* sized by its sink count and moved to its sinks' centroid
#      (the top never had it: QB11_ICG 0; r39_v top ICGs all CKLNQD1 where DC put them)
#   3. impl/r14/cts14.tcl (the top clock skeleton + TritonCTS leaves, unchanged)
set ::env(QB44_CTS_PRE) ""
source [file normalize $::QB_R14/../r44/icgsplit44.tcl]
if {[qb_env QB43_ICG 1]} { source $::QB_R6C/icg.tcl; qb6c_icg }
source $::QB_R14/cts14.tcl
