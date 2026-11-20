source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
read_db $::OUT/db/[qc_env R33_DB cts_rt].odb
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]
array set A {}; array set N {}
foreach o [$blk getObstructions] { set b [$o getBBox]; set l [[$b getTechLayer] getName]; set A($l) [expr {([info exists A($l)] ? $A($l) : 0) + [$b getDX] * [$b getDY] / $u / $u}]; incr N($l) }
foreach l [lsort [array names A]] { puts [format "R33O obstruction %s n %d area %.0f um2" $l $N($l) $A($l)] }
puts "R33O blockages [llength [$blk getBlockages]] obstructions [llength [$blk getObstructions]]"
foreach l {M5 M6 M7 M8 M9} { set tl [[ord::get_db_tech] findLayer $l]; set tg [$blk findTrackGrid $tl]; puts "R33O $l pitch [$tl getPitch] width [$tl getWidth] spacing [$tl getSpacing] tracks y [llength [$tg getGridY]] x [llength [$tg getGridX]]" }
exit
