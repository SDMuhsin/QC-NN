# trace clock path from each $::env(PINS) (inst names) back to the root: driver inst, master, location, net fanout, net bbox hpwl
read_db $::env(ODB)
set blk [ord::get_db_block]
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
proc nbb {net} { global u; set x0 1e12; set y0 1e12; set x1 -1e12; set y1 -1e12; set n 0
  foreach s [$net getITerms] { set b [[$s getInst] getBBox]; set x [expr {[$b xMin]/$u}]; set y [expr {[$b yMin]/$u}]
    set x0 [expr {min($x0,$x)}]; set x1 [expr {max($x1,$x)}]; set y0 [expr {min($y0,$y)}]; set y1 [expr {max($y1,$y)}]; incr n }
  return [format "fo %d hpwl %.0f" [expr {$n-1}] [expr {$x1-$x0+$y1-$y0}]] }
foreach p $::env(PINS) {
  set i [$blk findInst $p]; if {$i eq "NULL"} { puts "TR $p missing"; continue }
  puts "TR ==== $p"
  set it [$i findITerm CP]; if {$it eq "NULL"} { set it [$i findITerm CLK] }
  for {set k 0} {$k < 30} {incr k} {
    set net [$it getNet]; if {$net eq "NULL"} break
    set drv ""; foreach s [$net getITerms] { if {[$s isOutputSignal]} { set drv $s } }
    if {$drv eq ""} { puts "TR   <- port/root net [$net getName] [nbb $net]"; break }
    set d [$drv getInst]; set b [$d getBBox]
    puts [format "TR   <- %-45s %-8s (%.0f,%.0f) %s" [$d getName] [[$d getMaster] getName] [expr {[$b xMin]/$u}] [expr {[$b yMin]/$u}] [nbb $net]]
    set it [$d findITerm I]; if {$it eq "NULL"} { set it [$d findITerm CP] }; if {$it eq "NULL"} break
  }
}
