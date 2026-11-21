# R36: std-cell rows crossing x = R36_X [2000] um above y R36_Y0 [5000] (y ranges, merged), db R36_DB [pdn]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/[qc_env R36_DB pdn].odb
set blk [ord::get_db_block]; set u [$blk getDefUnits]; set X [expr {[qc_env R36_X 2000]*$u}]; set Y0 [expr {[qc_env R36_Y0 5000]*$u}]
set ys {}
foreach r [$blk getRows] { set b [$r getBBox]; if {[$b xMin] <= $X && [$b xMax] >= $X && [$b yMin] >= $Y0} { lappend ys [list [$b yMin] [$b yMax]] } }
set ys [lsort -integer -index 0 $ys]; set cur {}
foreach r $ys { if {$cur ne "" && [lindex $r 0] <= [lindex $cur 1]} { lset cur 1 [lindex $r 1] } else { if {$cur ne ""} { puts "R36_ROWS y [expr {[lindex $cur 0]/double($u)}] .. [expr {[lindex $cur 1]/double($u)}]" }; set cur $r } }
if {$cur ne ""} { puts "R36_ROWS y [expr {[lindex $cur 0]/double($u)}] .. [expr {[lindex $cur 1]/double($u)}]" }
foreach i [$blk getInsts] { if {[[$i getMaster] getName] eq "qb_w_204x144m2"} { set b [$i getBBox]; if {[$b xMin] <= $X && [$b xMax] >= $X} { puts "R36_W [$i getOrient] y [expr {[$b yMin]/double($u)}] .. [expr {[$b yMax]/double($u)}]" } } }
exit
