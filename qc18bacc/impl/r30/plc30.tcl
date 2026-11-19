# R30 probe (read-only): std-cell placement legality vs the row grid of a run's db (R30_DB [grt]):
# y on a row origin, orientation = row orientation, x on the site grid, placement status.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R30_DB grt]
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]
array set ro {}
set rx0 ""; set sw 0
foreach r [$blk getRows] { lassign [$r getOrigin] x y; set ro($y) [$r getOrient]; if {$rx0 eq ""} { set rx0 $x; set sw [[$r getSite] getWidth] } }
array set cnt {}
set ex {}
foreach i [$blk getInsts] {
  set m [$i getMaster]; if {[$m isBlock]} continue
  incr cnt(all)
  incr cnt(st_[$i getPlacementStatus])
  lassign [$i getLocation] x y
  if {![info exists ro($y)]} { incr cnt(y_off_row); if {[llength $ex] < 8} { lappend ex [list [$i getName] [$m getName] [expr {$x/$u}] [expr {$y/$u}] [$i getOrient] [$i getPlacementStatus]] }; continue }
  if {$ro($y) ne [$i getOrient] && !($ro($y) eq "R0" && [$i getOrient] eq "MY") && !($ro($y) eq "MX" && [$i getOrient] eq "R180")} {
     incr cnt(orient_bad); if {[llength $ex] < 16} { lappend ex [list ORIENT [$i getName] [$m getName] [expr {$y/$u}] [$i getOrient] row $ro($y)] } }
  if {($x - $rx0) % $sw != 0} { incr cnt(x_off_site) }
}
puts "R30P [array get cnt]"
foreach e $ex { puts "R30P ex $e" }
exit
