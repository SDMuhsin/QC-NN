# R44: clock latency decomposition at a post-CTS checkpoint (QB_DB, default cts), placement parasitics, tt.
# For every register clock pin: arrival; for gated pins, the ICG (walk back through buffers): ICG CP arrival, Q arrival.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env QB_DB cts]
set_propagated_clock [all_clocks]
estimate_parasitics -placement
set blk [ord::get_db_block]
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
proc arr {pin} { foreach pr {arrival_max_rise max_rise_arrival} { if {![catch {get_property $pin $pr} v] && $v ne "" && ![string match -nocase *inf* $v]} { if {$v < 1e-6} {set v [expr {$v*1e9}]}; return $v } }; return "" }
proc xy {i} { global u; set b [$i getBBox]; return [list [expr {([$b xMin]+[$b xMax])/2.0/$u}] [expr {([$b yMin]+[$b yMax])/2.0/$u}]] }
# map net -> driving ICG through clock buffers
proc drv_icg {net} {
  for {set k 0} {$k < 40} {incr k} {
    set d ""; foreach s [$net getITerms] { if {[$s isOutputSignal]} { set d $s } }
    if {$d eq ""} { return "" }
    set i [$d getInst]; set m [[$i getMaster] getName]
    if {[string match CKLNQD* $m]} { return $i }
    set in ""; foreach s [$i getITerms] { if {[$s isInputSignal] && [$s getNet] ne "NULL" && ![[$s getNet] isSpecial]} { set in [$s getNet] } }
    if {$in eq "" || [llength [$i getITerms]] > 4} { return "" }
    set net $in
  }
  return ""
}
array set cache {}; set ug {}; array set G {}
foreach p [all_registers -clock_pins] {
  set a [arr $p]; if {$a eq ""} continue
  set it [sta::sta_to_db_pin $p]; if {$it eq "" || $it eq "NULL"} continue
  set net [$it getNet]; if {$net eq "NULL"} continue
  set nn [$net getName]
  if {![info exists cache($nn)]} { set cache($nn) [drv_icg $net] }
  set g $cache($nn)
  if {$g eq ""} { lappend ug $a } else { lappend G([$g getName]) [list $a [xy [$it getInst]]] }
}
proc q {l} { set l [lsort -real $l]; set n [llength $l]; if {!$n} { return "n 0" }
  format "n %d min %.3f p10 %.3f p50 %.3f p90 %.3f p99 %.3f max %.3f" $n [lindex $l 0] [lindex $l [expr {$n/10}]] [lindex $l [expr {$n/2}]] [lindex $l [expr {9*$n/10}]] [lindex $l [expr {99*$n/100}]] [lindex $l end] }
set ugs [lsort -real $ug]; set p50 [lindex $ugs [expr {[llength $ugs]/2}]]
puts "L44 ungated [q $ug]"
set gl {}; set rows {}
foreach g [array names G] {
  set i [$blk findInst $g]; set cp [arr [get_pins $g/CP]]; set qa [arr [get_pins $g/Q]]
  set mx -1; set x0 1e9; set x1 -1e9; set y0 1e9; set y1 -1e9; set sx 0; set sy 0
  foreach r $G($g) { lassign $r a pxy; lappend gl $a; set mx [expr {max($mx,$a)}]; lassign $pxy x y
    set x0 [expr {min($x0,$x)}]; set x1 [expr {max($x1,$x)}]; set y0 [expr {min($y0,$y)}]; set y1 [expr {max($y1,$y)}]; set sx [expr {$sx+$x}]; set sy [expr {$sy+$y}] }
  set n [llength $G($g)]; lassign [xy $i] ix iy
  set dc [expr {abs($ix-($x0+$x1)/2)+abs($iy-($y0+$y1)/2)}]
  lappend rows [list $mx $n $cp $qa [expr {$x1-$x0+$y1-$y0}] $dc [[$i getMaster] getName] $g]
}
puts "L44 gated   [q $gl]"
puts "L44 icgs [llength $rows] ungated_p50 $p50"
set cpl {}; set icgd {}; set sub {}
foreach r $rows { lassign $r mx n cp qa bb dc; if {$cp ne "" && $qa ne ""} { lappend cpl $cp; lappend icgd [expr {$qa-$cp}]; lappend sub [expr {$mx-$qa}] } }
puts "L44 icg_CP_arrival [q $cpl]"
puts "L44 icg_delay      [q $icgd]"
puts "L44 subtree_max    [q $sub]"
set rows [lsort -real -decreasing -index 0 $rows]
puts "L44 worst: max_sink_lat n icgCP icgQ sink_bbox_hpwl icg_to_bbox_center master name"
foreach r [lrange $rows 0 19] { puts [format "L44W %.3f %3d %s %s %6.0f %6.0f %s %s" {*}$r] }
# correlation: excess vs bbox
foreach lim {100 200 400 800 100000} { set c 0; set s 0.0; set e 0
  foreach r $rows { lassign $r mx n cp qa bb; if {$bb < $lim && $bb >= [expr {$lim==100?0:($lim==100000?800:$lim/2)}]} { incr c; set s [expr {$s+$mx-$p50}] } }
  if {$c} { puts [format "L44B bbox<%d: %d icgs mean max-sink excess over ungated p50 %.3f" $lim $c [expr {$s/$c}]] } }
exit
