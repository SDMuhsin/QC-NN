# R30 probe (read-only): contents of one window (R30_WIN "x0 y0 x1 y1" um) of a run's db (R30_DB [grt]):
# macros / blockages overlapping, std cells by master and name class, pins, rows, PG shapes per layer.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
qc_read_liberty
read_db $::OUT/db/[qc_env R30_DB grt].odb
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]
lassign [qc_env R30_WIN "1350 1850 1400 1900"] X0 Y0 X1 Y1
proc ov {b} { expr {[$b xMax]/$::u > $::X0 && [$b xMin]/$::u < $::X1 && [$b yMax]/$::u > $::Y0 && [$b yMin]/$::u < $::Y1} }
foreach i [$blk getInsts] { if {[[$i getMaster] isBlock] && [ov [$i getBBox]]} { set b [$i getBBox]; puts [format "R30B macro %s %s %.1f %.1f %.1f %.1f" [$i getName] [[$i getMaster] getName] [expr {[$b xMin]/$u}] [expr {[$b yMin]/$u}] [expr {[$b xMax]/$u}] [expr {[$b yMax]/$u}]] } }
foreach bk [$blk getBlockages] { set b [$bk getBBox]; if {[ov $b]} { puts [format "R30B blockage %.1f %.1f %.1f %.1f maxdens %s" [expr {[$b xMin]/$u}] [expr {[$b yMin]/$u}] [expr {[$b xMax]/$u}] [expr {[$b yMax]/$u}] [$bk getMaxDensity]] } }
foreach o [$blk getObstructions] { set b [$o getBBox]; if {[ov $b]} { puts [format "R30B obstruction %s %.1f %.1f %.1f %.1f" [[$b getTechLayer] getName] [expr {[$b xMin]/$u}] [expr {[$b yMin]/$u}] [expr {[$b xMax]/$u}] [expr {[$b yMax]/$u}]] } }
array set mc {}; array set nc {}; set a 0.0; set np 0; set nn 0
foreach i [$blk getInsts] {
  set m [$i getMaster]; if {[$m isBlock]} continue
  if {![ov [$i getBBox]]} continue
  incr mc([$m getName]); set a [expr {$a + [$m getWidth]*[$m getHeight]/$u/$u}]
  set c [regsub -all {\d+} [lindex [split [$i getName] /] end] N]; incr nc($c)
  foreach it [$i getITerms] { if {[$it getNet] ne "NULL" && [[$it getNet] getSigType] in {SIGNAL CLOCK}} { incr np } }
}
set l {}; foreach k [array names mc] { lappend l [list $k $mc($k)] }
puts "R30B std_area [format %.0f $a] signal_pins $np masters [lrange [lsort -integer -decreasing -index 1 $l] 0 14]"
set l {}; foreach k [array names nc] { lappend l [list $k $nc($k)] }
puts "R30B names [lrange [lsort -integer -decreasing -index 1 $l] 0 14]"
if {[qc_env R30_LIST 0]} { foreach i [$blk getInsts] { set m [$i getMaster]; if {[$m isBlock] || ![ov [$i getBBox]]} continue; puts "R30L [$i getName] [$m getName]" } }
exit
