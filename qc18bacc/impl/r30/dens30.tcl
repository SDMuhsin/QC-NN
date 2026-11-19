# R30 probe (read-only): std-cell density per 50-um bin (std area / bin area outside macros + halo) of a run's db
# (R30_DB), distribution + std area by class (repair buffers vs netlist cells).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set db [qc_env R30_DB grt]
qc_read_liberty
read_db $::OUT/db/$db.odb
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]
set die [$blk getDieArea]; set W [expr {[$die xMax] / $u}]; set H [expr {[$die yMax] / $u}]
set B 50.0; set nx [expr {int(ceil($W / $B))}]; set ny [expr {int(ceil($H / $B))}]
set halo [lindex [p MACRO_HALO] 0]
set core [$blk getCoreArea]
array set cap {}; array set use {}
for {set i 0} {$i < $nx} {incr i} { for {set j 0} {$j < $ny} {incr j} {
  set x0 [expr {max($i * $B, [$core xMin] / $u)}]; set x1 [expr {min(($i + 1) * $B, [$core xMax] / $u)}]
  set y0 [expr {max($j * $B, [$core yMin] / $u)}]; set y1 [expr {min(($j + 1) * $B, [$core yMax] / $u)}]
  set cap($i,$j) [expr {max(0.0, $x1 - $x0) * max(0.0, $y1 - $y0)}]; set use($i,$j) 0.0 } }
set nm 0
foreach i [$blk getInsts] {
  if {![[$i getMaster] isBlock]} continue
  incr nm
  set b [$i getBBox]
  set x0 [expr {[$b xMin] / $u - $halo}]; set x1 [expr {[$b xMax] / $u + $halo}]
  set y0 [expr {[$b yMin] / $u - $halo}]; set y1 [expr {[$b yMax] / $u + $halo}]
  for {set ii [expr {max(0, int($x0 / $B))}]} {$ii <= min($nx - 1, int($x1 / $B))} {incr ii} {
    for {set jj [expr {max(0, int($y0 / $B))}]} {$jj <= min($ny - 1, int($y1 / $B))} {incr jj} {
      set ox [expr {max(0.0, min($x1, ($ii + 1) * $B) - max($x0, $ii * $B))}]
      set oy [expr {max(0.0, min($y1, ($jj + 1) * $B) - max($y0, $jj * $B))}]
      set cap($ii,$jj) [expr {max(0.0, $cap($ii,$jj) - $ox * $oy)}]
    }
  }
}
array set cls {}; set tot 0.0; set npin 0
foreach i [$blk getInsts] {
  set m [$i getMaster]; if {[$m isBlock]} continue
  set a [expr {[$m getWidth] * [$m getHeight] / $u / $u}]
  lassign [$i getLocation] x y
  set k "[expr {min($nx - 1, int($x / $u / $B))}],[expr {min($ny - 1, int($y / $u / $B))}]"
  set use($k) [expr {$use($k) + $a}]
  set np 0; foreach it [$i getITerms] { set nn [$it getNet]; if {$nn ne "NULL" && [$nn getSigType] in {SIGNAL CLOCK}} { incr np } }
  set pins($k) [expr {([info exists pins($k)] ? $pins($k) : 0) + $np}]
  set c [lindex [split [$i getName] /] end]
  set c [expr {[regexp {^(wire|fanout|max_cap|split|rebuffer|load_slew|gain|max_length|hold|clkbuf|clkload|delay|place)\d*} $c - cc] ? $cc : "other"}]
  set cls($c) [expr {([info exists cls($c)] ? $cls($c) : 0.0) + $a}]
  set tot [expr {$tot + $a}]
}
set ds {}; set fa 0.0; set fu 0.0
foreach k [array names cap] {
  if {$cap($k) < 0.5 * $B * $B} continue
  lappend ds [expr {$use($k) / $cap($k)}]; set fa [expr {$fa + $cap($k)}]; set fu [expr {$fu + $use($k)}]
}
set ds [lsort -real $ds]; set n [llength $ds]
proc pc {l q} { return [lindex $l [expr {min([llength $l] - 1, int($q * [llength $l]))}]] }
set g85 0; set g95 0; foreach d $ds { if {$d >= 0.85} { incr g85 }; if {$d >= 0.95} { incr g95 } }
puts [format "R30DENS %s macros %d std_um2 %.0f bins(>=50%% free) %d mean %.3f p50 %.3f p90 %.3f p99 %.3f max %.3f bins>=0.85 %d >=0.95 %d" \
  $db $nm $tot $n [expr {$fu / $fa}] [pc $ds 0.5] [pc $ds 0.9] [pc $ds 0.99] [lindex $ds end] $g85 $g95]
set l {}; foreach c [array names cls] { lappend l [list $c [format %.0f $cls($c)]] }
puts "R30DENS $db class_um2 [lsort -integer -decreasing -index 1 $l]"
if {[qc_env R30_DUMP ""] ne ""} { set f [open [qc_env R30_DUMP] w]; foreach k [array names cap] { puts $f "$k $cap($k) $use($k) [expr {[info exists pins($k)] ? $pins($k) : 0}]" }; close $f }
foreach k [qc_env R30_BINS ""] { if {[info exists cap($k)]} { puts [format "R30DENS %s bin %s cap %.0f std %.0f dens %.3f" $db $k $cap($k) $use($k) [expr {$cap($k) > 0 ? $use($k) / $cap($k) : -1}]] } }
exit
