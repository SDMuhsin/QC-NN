# ICG handling before CTS in every design (R44, results/r44.md; PRE_CTS_TCL of blocks/col, blocks/act, sourced by
# cts/hub_cts_pre.tcl and cts/top_cts_pre.tcl):
#   1. cts/icg_split.tcl: an ICG whose gated sinks form two groups more than QB44_SPLIT [400] um apart (x or y) is cloned
#      and the smaller group moves to the clone, so TritonCTS builds two compact gated trees instead of one H-tree centred
#      between the groups (hub g_wbc: 2 x 2 mm detour, the R40 hold residue)
#   2. cts/icg_size.tcl: every CKLNQD* sized by its gated-sink count and moved to its sinks' centroid (legalised by the
#      CTS step's detailed placement)
source $::QBF/cts/icg_split.tcl
qb44_split [qb_env QB44_SPLIT 400]
source $::QBF/cts/icg_size.tcl
qb6c_icg
