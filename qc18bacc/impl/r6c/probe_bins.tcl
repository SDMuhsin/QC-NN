# R6c probe (read-only): local row fill of QB_RUN/db/QB_DB.odb on QB_BIN-um bins (100): histogram of bins by
# std-cell area / row area, row area in each class, and the 12 fullest bin rows (y bands) summary.
set run $::env(QB_RUN); set db [expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "place"}]
read_db $run/db/$db.odb
set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
set g [expr {round([expr {[info exists ::env(QB_BIN)] ? $::env(QB_BIN) : 100}] * $u)}]
array set ra {}; array set ca {}
foreach r [$blk getRows] {
    set b [$r getBBox]; set j [expr {[$b yMin] / $g}]
    for {set x [$b xMin]} {$x < [$b xMax]} {} {
        set i [expr {$x / $g}]; set xe [expr {min([$b xMax], ($i + 1) * $g)}]
        set k "$i,$j"; if {![info exists ra($k)]} { set ra($k) 0.0; set ca($k) 0.0 }
        set ra($k) [expr {$ra($k) + double($xe - $x) * [$b dy]}]; set x $xe
    }
}
foreach i [$blk getInsts] {
    set m [$i getMaster]; if {[$m isBlock]} continue
    lassign [$i getLocation] x y; set k "[expr {$x / $g}],[expr {$y / $g}]"
    if {[info exists ca($k)]} { set ca($k) [expr {$ca($k) + double([$m getWidth]) * [$m getHeight]}] }
}
set cls {0.5 0.7 0.8 0.85 0.9 0.95 1e9}
foreach c $cls { set hn($c) 0; set hr($c) 0.0 }
foreach k [array names ra] {
    if {$ra($k) < 0.05 * $g * $g} continue
    set f [expr {$ca($k) / $ra($k)}]
    foreach c $cls { if {$f <= $c} { incr hn($c); set hr($c) [expr {$hr($c) + $ra($k)}]; break } }
}
set s "BINS db $db bin_um [expr {$g / $u}]"
set lo 0
foreach c $cls { append s [format " %s-%s: %d bins %.3f mm2" $lo $c $hn($c) [expr {$hr($c) / $u / $u / 1e6}]]; set lo $c }
puts $s
