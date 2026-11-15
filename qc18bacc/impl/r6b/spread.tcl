# impl/r6b: per-group placement statistics of a checkpoint (QB_RUN, QB_DB default place): cells of each R6a group
# (grp.txt) outside the group's rectangles, displacement from the standalone group placement (grp_<g>.pos):
# mean / p99 / max, bounding box of the group's cells; repair buffers (rsz names) count / area by region.
read_db $::env(QB_RUN)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "place"}].odb
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
array set R {}
set f [open $::env(QB_RUN)/mplace.tcl.groups]
while {[gets $f l] >= 0} { set w [split [string trim $l] " "]; set R([lindex $w 0]) {}; foreach {a b c d} [lrange $w 1 end] { lappend R([lindex $w 0]) [list [expr {$a * $u}] [expr {$b * $u}] [expr {$c * $u}] [expr {$d * $u}]] } }
close $f
proc inrect {rs x y} { foreach r $rs { lassign $r a b c d; if {$x >= $a && $x < $c && $y >= $b && $y < $d} { return 1 } }; return 0 }
proc where {x y} { foreach g {S WA W N} { if {[inrect $::R($g) $x $y]} { return $g } }; return array }
foreach g {S WA W N} {
    array unset p0; array set p0 {}
    set f [open $::env(QB_RUN)/grp_$g[expr {[info exists ::env(QB_POS_TAG)] ? $::env(QB_POS_TAG) : ""}].pos]
    while {[gets $f l] >= 0} { set w [split $l " "]; set p0([lindex $w 0]) [lrange $w 1 2] }
    close $f
    set n 0; set out 0; set ds {}; set x1 1e12; set y1 1e12; set x2 -1e12; set y2 -1e12
    foreach nm [array names p0] {
        set i [$blk findInst $nm]; if {$i eq "NULL" || $i eq ""} continue
        lassign [$i getLocation] x y; lassign $p0($nm) a b
        incr n; if {![inrect $R($g) $x $y]} { incr out }
        lappend ds [expr {(abs($x - $a) + abs($y - $b)) / $u}]
        set x1 [expr {min($x1, $x)}]; set y1 [expr {min($y1, $y)}]; set x2 [expr {max($x2, $x)}]; set y2 [expr {max($y2, $y)}]
    }
    set ds [lsort -real $ds]; set k [llength $ds]
    set mean 0.0; foreach d $ds { set mean [expr {$mean + $d}] }
    puts [format "SPREAD %-2s cells %d outside_rect %d disp_um mean %.1f p99 %.1f max %.1f bbox_um %.0f %.0f %.0f %.0f" $g $n $out \
        [expr {$mean / max(1, $k)}] [lindex $ds [expr {int(0.99 * ($k - 1))}]] [lindex $ds end] \
        [expr {$x1 / $u}] [expr {$y1 / $u}] [expr {$x2 / $u}] [expr {$y2 / $u}]]
}
array set bn {}; array set ba {}
foreach i [$blk getInsts] {
    if {![regexp {^(wire|fanout|max_length|load_slew|max_cap|split|rebuffer|gain|hold|clkbuf|clkload|cts)} [$i getName] -> kind]} continue
    set m [$i getMaster]; lassign [$i getLocation] x y
    set k "$kind@[where $x $y]"
    if {![info exists bn($k)]} { set bn($k) 0; set ba($k) 0.0 }
    incr bn($k); set ba($k) [expr {$ba($k) + [$m getWidth] / $u * [$m getHeight] / $u}]
}
foreach k [lsort [array names bn]] { puts [format "REPAIR %-24s n %7d area_mm2 %.4f" $k $bn($k) [expr {$ba($k) / 1e6}]] }
exit
