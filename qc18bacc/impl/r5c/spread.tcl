# PE-row spread metric (results/r5c.md): for every PE row r, the bounding box of the cells of
# u_core/g_r_<r>__g_c_0__u_pe/ (full: min / max of the cell boxes; and 10-90 % of the cell centres in x and y).
# Sourced by impl/r5c/place.tcl (qb5c_spread <tag>) and run standalone on any odb by spread_db.tcl.
proc qb5c_spread {tag} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    array set xs {}; array set ys {}; array set bb {}
    foreach i [$blk getInsts] {
        if {![regexp {^u_core/g_r_(\d+)__g_c_0__u_pe/} [$i getName] -> r]} { continue }
        set b [$i getBBox]
        lappend xs($r) [expr {([$b xMin] + [$b xMax]) / 2.0 / $u}]; lappend ys($r) [expr {([$b yMin] + [$b yMax]) / 2.0 / $u}]
        if {![info exists bb($r)]} { set bb($r) [list [$b xMin] [$b yMin] [$b xMax] [$b yMax]] } else {
            lassign $bb($r) a c d e
            set bb($r) [list [expr {min($a, [$b xMin])}] [expr {min($c, [$b yMin])}] [expr {max($d, [$b xMax])}] [expr {max($e, [$b yMax])}]]
        }
    }
    set wmax 0.0; set hmax 0.0; set h90 0.0; set amax 0.0
    foreach r [lsort -integer [array names bb]] {
        lassign $bb($r) a c d e
        set w [expr {($d - $a) / double($u)}]; set h [expr {($e - $c) / double($u)}]
        set lx [lsort -real $xs($r)]; set ly [lsort -real $ys($r)]; set k [llength $lx]
        set x10 [lindex $lx [expr {int(0.1 * $k)}]]; set x90 [lindex $lx [expr {int(0.9 * $k)}]]
        set y10 [lindex $ly [expr {int(0.1 * $k)}]]; set y90 [lindex $ly [expr {int(0.9 * $k)}]]
        set wmax [expr {max($wmax, $w)}]; set hmax [expr {max($hmax, $h)}]; set h90 [expr {max($h90, $y90 - $y10)}]
        set amax [expr {max($amax, $w * $h)}]
        qc_log [format "r5c spread %s row %2d cells %5d bbox x %5.1f-%5.1f y %6.1f-%6.1f (%5.1f x %5.1f um) x10-90 %5.1f-%5.1f y10-90 %6.1f-%6.1f (%4.0f um)" \
            $tag $r $k [expr {$a / double($u)}] [expr {$d / double($u)}] [expr {$c / double($u)}] [expr {$e / double($u)}] $w $h $x10 $x90 $y10 $y90 [expr {$y90 - $y10}]]
    }
    qc_summary [format "r5c_spread_%s max_bbox_w_um %.1f max_bbox_h_um %.1f max_y10_90_um %.1f max_bbox_area_um2 %.0f" $tag $wmax $hmax $h90 $amax]
}
