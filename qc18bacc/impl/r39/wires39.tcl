# R39 probe (read-only): every routed signal-wire shape and via box of db/<R39_DB [route_dr]> that touches the box of
# instance <R39_INST [u_act_blk]> grown by 2 um, as "<layer> x1 y1 x2 y2 <net>" (um, relative to the instance origin)
# -> rpt/r39_wires_<inst>.txt.  For a block-view swap check against the new LEF OBS (impl/r39/obsclash39.py).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
read_db $::OUT/db/[expr {[info exists ::env(R39_DB)] ? $::env(R39_DB) : "route_dr"}].odb
set b [ord::get_db_block]; set u [$b getDefUnits]
set in [expr {[info exists ::env(R39_INST)] ? $::env(R39_INST) : "u_act_blk"}]
set i [$b findInst $in]; set bb [$i getBBox]; lassign [$i getLocation] ox oy
set g [expr {2 * $u}]
set X1 [expr {[$bb xMin] - $g}]; set Y1 [expr {[$bb yMin] - $g}]; set X2 [expr {[$bb xMax] + $g}]; set Y2 [expr {[$bb yMax] + $g}]
set f [open $::OUT/rpt/r39_wires_$in.txt w]; set n 0
foreach net [$b getNets] {
    if {[$net getSigType] ne "SIGNAL" && [$net getSigType] ne "CLOCK"} continue
    set w [$net getWire]; if {$w eq "NULL"} continue
    foreach s [$w getShapes] {
        if {[$s xMax] < $X1 || [$s xMin] > $X2 || [$s yMax] < $Y1 || [$s yMin] > $Y2} continue
        set l [$s getTechLayer]; if {$l eq "NULL"} continue
        puts $f [format "%s %.3f %.3f %.3f %.3f %s" [$l getName] [expr {([$s xMin]-$ox)/double($u)}] [expr {([$s yMin]-$oy)/double($u)}] [expr {([$s xMax]-$ox)/double($u)}] [expr {([$s yMax]-$oy)/double($u)}] [$net getName]]
        incr n
    }
}
close $f
puts "R39_WIRES $in $n shapes"
