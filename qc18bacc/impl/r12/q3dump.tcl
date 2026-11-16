# R12 Q3: routing obstructions of a checkpoint (QB_DB, default grt_pl3) for q3.py (results/r12.md):
#   L <layer> <H|V> <pitch um> <track-grid count>       routing layers (pitch from the track grid)
#   O <layer> <x0> <y0> <x1> <y1> <kind>                 macro OBS / macro pin shapes / special-net wires / block obstructions
# -> QB12_OUT (default $QC_PNR_OUT/rpt/r12_obs.txt)
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env QB_DB grt_pl3].odb
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set blk [ord::get_db_block]
set f [open [qc_env QB12_OUT $::OUT/rpt/r12_obs.txt] w]
foreach l [[ord::get_db_tech] getLayers] {
    if {[$l getType] ne "ROUTING"} continue
    set tg [$blk findTrackGrid $l]; set p 0; set n 0
    if {$tg ne "NULL"} {
        set d [expr {[$l getDirection] eq "HORIZONTAL" ? "H" : "V"}]
        if {$d eq "H"} { set n [$tg getNumGridPatternsY]; if {$n} { lassign [$tg getGridPatternY 0] o c s; set p [expr {$s / $u}]; set n $c } } else {
                         set n [$tg getNumGridPatternsX]; if {$n} { lassign [$tg getGridPatternX 0] o c s; set p [expr {$s / $u}]; set n $c } }
    }
    puts $f "L [$l getName] [expr {[$l getDirection] eq "HORIZONTAL" ? "H" : "V"}] $p $n"
}
proc bx {f ln b k} { puts $f [format "O %s %.3f %.3f %.3f %.3f %s" $ln [expr {[$b xMin] / $::u}] [expr {[$b yMin] / $::u}] [expr {[$b xMax] / $::u}] [expr {[$b yMax] / $::u}] $k] }
set ::u $u
proc tx {f ln b ax ay sw fx fy k} {
    if {$sw} { set p0 [$b yMin]; set p1 [$b yMax]; set q0 [$b xMin]; set q1 [$b xMax] } else { set p0 [$b xMin]; set p1 [$b xMax]; set q0 [$b yMin]; set q1 [$b yMax] }
    set x0 [expr {$ax + $fx * $p0}]; set x1 [expr {$ax + $fx * $p1}]
    set y0 [expr {$ay + $fy * $q0}]; set y1 [expr {$ay + $fy * $q1}]
    puts $f [format "O %s %.3f %.3f %.3f %.3f %s" $ln [expr {min($x0, $x1) / $::u}] [expr {min($y0, $y1) / $::u}] [expr {max($x0, $x1) / $::u}] [expr {max($y0, $y1) / $::u}] $k]
}
foreach i [$blk getInsts] {
    set m [$i getMaster]; if {![$m isBlock]} continue
    set ib [$i getBBox]; set o [$i getOrient]
    # X = ax + fx * (sw ? y : x), Y = ay + fy * (sw ? x : y)
    array set OR {R0 {0 1 1} MX {0 1 -1} MY {0 -1 1} R180 {0 -1 -1} R90 {1 -1 1} R270 {1 1 -1} MXR90 {1 1 1} MYR90 {1 -1 -1}}
    lassign $OR($o) sw fx fy
    set ax [expr {$fx > 0 ? [$ib xMin] : [$ib xMax]}]; set ay [expr {$fy > 0 ? [$ib yMin] : [$ib yMax]}]
    foreach b [$m getObstructions] {
        set l [$b getTechLayer]; if {$l eq "NULL" || [$l getType] ne "ROUTING"} continue
        tx $f [$l getName] $b $ax $ay $sw $fx $fy obs
    }
    foreach mt [$m getMTerms] { foreach mp [$mt getMPins] { foreach b [$mp getGeometry] {
        set l [$b getTechLayer]; if {$l eq "NULL" || [$l getType] ne "ROUTING"} continue
        tx $f [$l getName] $b $ax $ay $sw $fx $fy pin } } }
}
foreach o [$blk getObstructions] { set b [$o getBBox]; set l [$b getTechLayer]; if {$l ne "NULL"} { bx $f [$l getName] $b blkobs } }
set nv 0
foreach n [$blk getNets] {
    if {![$n isSpecial]} continue
    foreach w [$n getSWires] { foreach b [$w getWires] {
        if {[$b isVia]} { incr nv; continue }
        bx $f [[$b getTechLayer] getName] $b pdn } }
}
close $f
puts "R12 obs done, special vias skipped $nv"
exit
