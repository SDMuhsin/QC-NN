# PRE_CTS_TCL of blocks/top/top.cfg (results/r43.md; R44 gated-clock root cause, results/r44.md):
#   1. + 2. cts/icg_pre.tcl: ICGs whose sinks form two groups > 400 um apart are cloned BEFORE CTS; every CKLNQD* sized
#      by its sink count and moved to its sinks' centroid (r39_v top ICGs were all CKLNQD1 where DC put them)
#   3. cts/top_clock_tree.tcl: the top clock skeleton + TritonCTS on the leaf nets
source $::QBF/cts/icg_pre.tcl
source $::QBF/cts/top_clock_tree.tcl
