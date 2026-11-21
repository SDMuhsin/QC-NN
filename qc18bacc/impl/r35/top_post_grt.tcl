# R35 POST_GRT_TCL of impl/r35/top.cfg: impl/r14/post_grt14.tcl (clock table, GRT-parasitic balancing, classes) with
# its final impl/r9b/post_grt.tcl replaced by impl/r35/shim/post_grt.tcl (repair at GRT parasitics, then the real one).
set ::QB35_R9B_ORIG $::QB_R9B
set ::QB_R9B $::QB_R35/shim
source $::QB_R14/post_grt14.tcl
