# impl/r6c QB_SNAP3 1 (with QB_SNAP 1): replaces impl/r6b qb6_snap.  Same rule (a std cell whose origin lies inside a
# block / macro footprint + halo QB_SNAP_HALO um, the 8 abutted columns as one rectangle, goes to the nearest point
# just outside it), but only to a point that lies on a placement row (20-um x row bins of the core rows): r6b's snap
# also used the array's east edge, 10 um from the die edge where there are no rows, so spread3 found no room within
# 400 um for 22-34 k cells and moved them ~1.2-1.5 mm (r6c_p / r6c_g).  Candidates are the 4 edges and, if none is on
# a row, the 4 edges of the halo-enlarged rectangle stepped outwards by QB_SNAP3_STEP um (20) up to 10 steps.
proc qb6c_rowbins {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set bx [expr {round(20.0 * $u)}]
    set rh [[[lindex [$blk getRows] 0] getSite] getHeight]
    set core [$blk getCoreArea]; set cx0 [$core xMin]; set cy0 [$core yMin]
    array unset ::QB6C_RB
    foreach rw [$blk getRows] {
        set b [$rw getBBox]; set j [expr {([$b yMin] - $cy0) / $rh}]
        for {set i [expr {([$b xMin] - $cx0) / $bx}]} {$i <= ([$b xMax] - 1 - $cx0) / $bx} {incr i} { set ::QB6C_RB($i,$j) 1 }
    }
    return [list $bx $rh $cx0 $cy0]
}
proc qb6_snap {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    lassign [qb6c_rowbins] bx rh cx0 cy0
    set h [expr {round([qb_env QB_SNAP_HALO 8.0] * $u)}]
    set st [expr {round([qb_env QB_SNAP3_STEP 20.0] * $u)}]
    set rs {}; set ax1 1e18; set ay1 1e18; set ax2 -1e18; set ay2 -1e18
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isBlock]} continue
        set b [$i getBBox]
        if {[[$i getMaster] getName] eq "qb_col_blk"} {
            set ax1 [expr {min($ax1, [$b xMin])}]; set ay1 [expr {min($ay1, [$b yMin])}]
            set ax2 [expr {max($ax2, [$b xMax])}]; set ay2 [expr {max($ay2, [$b yMax])}]
        } else { lappend rs [list [expr {[$b xMin] - $h}] [expr {[$b yMin] - $h}] [expr {[$b xMax] + $h}] [expr {[$b yMax] + $h}]] }
    }
    lappend rs [list [expr {round($ax1) - $h}] [expr {round($ay1) - $h}] [expr {round($ax2) + $h}] [expr {round($ay2) + $h}]]
    set g [expr {100 * $u}]
    array set bk {}
    set k 0
    foreach r $rs {
        lassign $r a b c d
        for {set x [expr {$a / $g}]} {$x <= $c / $g} {incr x} { for {set y [expr {$b / $g}]} {$y <= $d / $g} {incr y} { lappend bk($x,$y) $k } }
        incr k
    }
    set n 0; set nst 0; set nno 0
    foreach i [$blk getInsts] {
        if {[[$i getMaster] isBlock] || [$i getPlacementStatus] ne "PLACED"} continue
        lassign [$i getLocation] x y
        set key "[expr {$x / $g}],[expr {$y / $g}]"
        if {![info exists bk($key)]} continue
        foreach k $bk($key) {
            lassign [lindex $rs $k] a b c d
            if {$x < $a || $x >= $c || $y < $b || $y >= $d} continue
            set w [[$i getMaster] getWidth]; set hh [[$i getMaster] getHeight]
            set best {}
            for {set s 0} {$s <= 10 && $best eq ""} {incr s} {
                set e [expr {$s * $st}]
                foreach {dd nx ny} [list [expr {$x - $a + $w + $e}] [expr {$a - $w - $e}] $y  [expr {$c - $x + $e}] [expr {$c + $e}] $y \
                                         [expr {$y - $b + $hh + $e}] $x [expr {$b - $hh - $e}]  [expr {$d - $y + $e}] $x [expr {$d + $e}]] {
                    if {![info exists ::QB6C_RB([expr {($nx - $cx0) / $bx}],[expr {($ny - $cy0) / $rh}])]} continue
                    if {$best eq "" || $dd < [lindex $best 0]} { set best [list $dd $nx $ny] }
                }
                if {$s > 0 && $best ne ""} { incr nst }
            }
            if {$best ne ""} { lassign $best dd nx ny; $i setLocation $nx $ny; incr n } else { incr nno }
            break
        }
    }
    qc_log "r6c: snap3 $n cells out of block / macro footprints onto rows ($nst via stepped edges, $nno without a row edge)"
}
