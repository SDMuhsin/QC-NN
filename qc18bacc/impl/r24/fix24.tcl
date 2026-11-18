# R24 (results/r24.md): legalisation of post-CTS repair cells (pc24.tcl QB24_MODE fix, or sourced alone).
# QB24_FIX (list of words):
#   mac   before DPL, every std cell whose centre lies over a macro (bbox + QB24_HALO um, default 7) is moved to the
#         nearest point just outside that macro (nearest of the 4 sides, clamped to the core) -> DPL only does local work
#   (none) plain detailed_placement
# QB24_DPL_ARGS: detailed_placement args (default P(DPL_ARGS))
proc qb24_macro_grid {} {
    if {[info exists ::QB24_MG]} { return }
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set h [expr {round([qb_env QB24_HALO 7.0] * $u)}]; set ::QB24_G [expr {50 * $u}]
    set c [$blk getCoreArea]; set ::QB24_CORE [list [$c xMin] [$c yMin] [$c xMax] [$c yMax]]
    array set ::QB24_MG {}
    set ::QB24_MB {}
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isBlock]} { continue }
        set b [$i getBBox]
        set r [list [expr {[$b xMin] - $h}] [expr {[$b yMin] - $h}] [expr {[$b xMax] + $h}] [expr {[$b yMax] + $h}]]
        set k [llength $::QB24_MB]; lappend ::QB24_MB $r
        lassign $r x0 y0 x1 y1
        for {set gx [expr {$x0 / $::QB24_G}]} {$gx <= $x1 / $::QB24_G} {incr gx} {
            for {set gy [expr {$y0 / $::QB24_G}]} {$gy <= $y1 / $::QB24_G} {incr gy} { lappend ::QB24_MG($gx,$gy) $k }
        }
    }
}
# move std cells over macros out; returns the count
proc qb24_unmacro {} {
    qb24_macro_grid
    lassign $::QB24_CORE cx0 cy0 cx1 cy1
    set n 0; set dsum 0
    foreach i [[ord::get_db_block] getInsts] {
        set m [$i getMaster]
        if {[$m isBlock] || [$i getPlacementStatus] ne "PLACED"} { continue }
        set b [$i getBBox]; set w [$b getDX]; set ht [$b getDY]
        set x [expr {[$b xMin] + $w / 2}]; set y [expr {[$b yMin] + $ht / 2}]
        set key "[expr {$x / $::QB24_G}],[expr {$y / $::QB24_G}]"
        if {![info exists ::QB24_MG($key)]} { continue }
        foreach k $::QB24_MG($key) {
            lassign [lindex $::QB24_MB $k] x0 y0 x1 y1
            if {$x <= $x0 || $x >= $x1 || $y <= $y0 || $y >= $y1} { continue }
            # nearest side, candidate centres just outside, clamped to the core
            set best {}
            foreach {d nx ny} [list [expr {$x - $x0}] [expr {$x0 - $w}] $y  [expr {$x1 - $x}] [expr {$x1 + $w}] $y \
                                    [expr {$y - $y0}] $x [expr {$y0 - $ht}]  [expr {$y1 - $y}] $x [expr {$y1 + $ht}]] {
                if {$nx < $cx0 + $w || $nx > $cx1 - $w || $ny < $cy0 + $ht || $ny > $cy1 - $ht} { continue }
                if {$best eq "" || $d < [lindex $best 0]} { set best [list $d $nx $ny] }
            }
            if {$best eq ""} { break }
            lassign $best d nx ny
            $i setLocation [expr {$nx - $w / 2}] [expr {$ny - $ht / 2}]
            incr n; set dsum [expr {$dsum + $d}]
            break
        }
    }
    qc_log [format "r24: unmacro moved %d cells, total %.0f um" $n [expr {$dsum / double([[ord::get_db_tech] getDbUnitsPerMicron])}]]
    return $n
}
proc qb24_fix_legal {tag} {
    set fx [qb_env QB24_FIX ""]
    if {"mac" in $fx} { qb24_unmacro }
    detailed_placement {*}[qb_env QB24_DPL_ARGS [p DPL_ARGS]]
    estimate_parasitics -placement
    qb_counts $tag
}
