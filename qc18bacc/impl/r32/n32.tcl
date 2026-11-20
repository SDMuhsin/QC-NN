# R32: new cells (R32_B not in R32_A) in a window R32_WIN {x0 y0 x1 y1} um: masters, area, the nets they drive (sink stems)
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set _f [open $::OUT/config.tcl]; set _t [read $_f]; close $_f
eval [string map {r31_snap/ r31_snap4/} $_t]
qc_config
qc_read_liberty
read_db $::OUT/db/$::env(R32_A).odb
array set P {}
foreach i [[ord::get_db_block] getInsts] { lassign [$i getLocation] x y; set P([$i getName]) [list $x $y] }
[ord::get_db] clear
read_db $::OUT/db/$::env(R32_B).odb
set blk [ord::get_db_block]
lassign $::env(R32_WIN) wx0 wy0 wx1 wy1
proc stem {n} { set n [regsub {/[^/]*$} $n ""]; return [regsub -all {\d+} $n N] }
array set M {}; array set A {}; array set S {}; array set D {}; set a_old 0.0; set a_new 0.0
foreach i [$blk getInsts] {
  set m [$i getMaster]; if {[$m isBlock]} continue
  lassign [$i getLocation] x y; set x [expr {$x/2000.0}]; set y [expr {$y/2000.0}]
  if {$x < $wx0 || $x > $wx1 || $y < $wy0 || $y > $wy1} continue
  set ar [expr {[$m getWidth]*[$m getHeight]/4.0e6}]
  if {[info exists P([$i getName])]} { set a_old [expr {$a_old+$ar}]; continue }
  set a_new [expr {$a_new+$ar}]
  incr M([$m getName]); 
  set nm [regsub {\d+$} [$i getName] ""]; incr D($nm)
  set o [$i findITerm Z]; if {$o eq "NULL"} continue
  foreach it [[$o getNet] getITerms] { if {![$it isOutputSignal]} { incr S([stem [[$it getInst] getName]]) } }
}
# cells that were in the window at A and are not any more
set gone 0; set gone_pcol 0
foreach i [$blk getInsts] {
  set n [$i getName]; if {![info exists P($n)]} continue
  lassign $P($n) x y; set x [expr {$x/2000.0}]; set y [expr {$y/2000.0}]
  if {$x < $wx0 || $x > $wx1 || $y < $wy0 || $y > $wy1} continue
  lassign [$i getLocation] x2 y2; set x2 [expr {$x2/2000.0}]; set y2 [expr {$y2/2000.0}]
  if {$x2 < $wx0 || $x2 > $wx1 || $y2 < $wy0 || $y2 > $wy1} { incr gone; if {[string match u_head/g_pcol_4__u_pc/* $n]} { incr gone_pcol } }
}
puts [format "R32N window %s old_cell_area_at_B %.0f new_cell_area %.0f window_area %.0f moved_out %d (pcol4 %d)" $::env(R32_WIN) $a_old $a_new [expr {($wx1-$wx0)*($wy1-$wy0)}] $gone $gone_pcol]
puts "R32N masters [lsort -stride 2 -index 1 -integer -decreasing [array get M]]"
puts "R32N name_prefix [lsort -stride 2 -index 1 -integer -decreasing [array get D]]"
set l {}; foreach k [array names S] { lappend l [list $k $S($k)] }
puts "R32N sinks [lrange [lsort -index 1 -integer -decreasing $l] 0 11]"
exit
