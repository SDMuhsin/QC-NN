# R30 probe (read-only): PDN special-wire shapes / vias per layer in a run's db (R30_DB [grt]).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R30_DB grt]
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]
array set ::nv {}; array set ::vb {}; array set ::nw {}; array set ::wa {}
foreach net [$blk getNets] {
  if {![$net isSpecial]} continue
  foreach sw [$net getSWires] {
    foreach b [$sw getWires] {
      if {[$b isVia]} {
        set vo [expr {[$b getTechVia] ne "NULL" ? [$b getTechVia] : [$b getBlockVia]}]
        set v [$vo getName]
        incr ::nv($v)
        if {![info exists ::vb($v)]} {
          set s {}
          foreach bx [$vo getBoxes] { lappend s [format "%s:%.3fx%.3f" [[$bx getTechLayer] getName] [expr {[$bx getDX]/$u}] [expr {[$bx getDY]/$u}]] }
          set ::vb($v) [lsort -unique $s]
        }
      } else {
        set l [[$b getTechLayer] getName]; incr ::nw($l)
        set ::wa($l) [expr {([info exists ::wa($l)] ? $::wa($l) : 0.0) + [$b getDX]/$u * [$b getDY]/$u}]
      }
    }
  }
}
foreach v [lsort [array names ::nv]] { puts "R30V $v n $::nv($v) [join $::vb($v) { }]" }
foreach l [lsort [array names ::nw]] { puts [format "R30W %s shapes %d area_um2 %.0f" $l $::nw($l) $::wa($l)] }
# a sample std cell: rail pins
foreach m {ND2D1 DFQD1 BUFFD16 INVD1} {
  set mm [[ord::get_db] findMaster $m]
  foreach mt [$mm getMTerms] {
    if {[$mt getName] ni {VDD VSS}} continue
    foreach p [$mt getMPins] { foreach g [$p getGeometry] { puts [format "R30C %s %s %s %.3f %.3f %.3f %.3f" $m [$mt getName] [[$g getTechLayer] getName] [expr {[$g xMin]/$u}] [expr {[$g yMin]/$u}] [expr {[$g xMax]/$u}] [expr {[$g yMax]/$u}]] } }
  }
  puts [format "R30C %s size %.3f x %.3f" $m [expr {[$mm getWidth]/$u}] [expr {[$mm getHeight]/$u}]]
}
exit
