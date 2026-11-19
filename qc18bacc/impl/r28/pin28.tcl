# R28: nearest instance pin (macro or std) of each DR marker centre.  On tau:
#   QC_PNR_OUT=<run> QB_DB [route_dr] QB28_PTS <file "x y" per line, um> openroad -exit pin28.tcl
# Prints "R28_PIN x y inst master pin layer pin_box(um) dist(um)" per point.
read_db $::env(QC_PNR_OUT)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "route_dr"}].odb
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]
set pts {}; set f [open $::env(QB28_PTS)]; while {[gets $f l] >= 0} { if {[llength $l] == 2} { lappend pts $l } }; close $f
foreach p $pts {
    lassign $p x y; set X [expr {$x * $u}]; set Y [expr {$y * $u}]; set best {}; set bd 1e18
    foreach i [$blk getInsts] {
        set b [$i getBBox]
        if {$X < [$b xMin] - 2000 || $X > [$b xMax] + 2000 || $Y < [$b yMin] - 2000 || $Y > [$b yMax] + 2000} continue
        foreach it [$i getITerms] {
            if {[$it getNet] eq "NULL"} continue
            foreach g [list [$it getBBox]] {
                set dx [expr {max(0, max([$g xMin] - $X, $X - [$g xMax]))}]; set dy [expr {max(0, max([$g yMin] - $Y, $Y - [$g yMax]))}]
                set d [expr {hypot($dx, $dy)}]
                if {$d < $bd} { set bd $d; set best [list [$i getName] [[$i getMaster] getName] [[$it getMTerm] getName] [lsort -unique [lmap pp [[$it getMTerm] getMPins] {lmap bx [$pp getGeometry] {[$bx getTechLayer] getName}}]] \
                    [format "%.3f %.3f %.3f %.3f" [expr {[$g xMin]/$u}] [expr {[$g yMin]/$u}] [expr {[$g xMax]/$u}] [expr {[$g yMax]/$u}]]] }
            }
        }
    }
    puts "R28_PIN $x $y $best [format %.3f [expr {$bd / $u}]]"
}
