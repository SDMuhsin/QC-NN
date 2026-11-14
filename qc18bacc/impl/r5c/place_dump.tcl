# PRE_PLACE_TCL of impl/r5c/pe_tile.cfg: after the (only) detailed placement of the standalone PE, write
# $OUT/tile.txt (instance x y orient; DBU relative to the core origin) and the template's own geometry line.
rename detailed_placement qb5c_dpl_orig
proc detailed_placement {args} {
    qb5c_dpl_orig {*}$args
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set core [$blk getCoreArea]
    set x0 [$core xMin]; set y0 [$core yMin]
    set fh [open $::OUT/tile.txt w]; set n 0; set a 0.0
    foreach i [$blk getInsts] {
        set m [$i getMaster]
        if {![$m isCore]} { continue }
        lassign [$i getLocation] x y
        puts $fh [list [$i getName] [expr {$x - $x0}] [expr {$y - $y0}] [$i getOrient]]
        incr n; set a [expr {$a + [$m getWidth] * double([$m getHeight]) / $u / $u}]
    }
    close $fh
    qc_summary [format "pe_tile cells %d area_um2 %.0f core_um %.1f x %.1f util %.3f" $n $a \
        [expr {[$core dx] / double($u)}] [expr {[$core dy] / double($u)}] [expr {$a * $u * $u / ([$core dx] * double([$core dy]))}]]
}
