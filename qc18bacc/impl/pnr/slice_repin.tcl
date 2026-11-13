# PRE_CTS_TCL of slice.cfg with QB_REPIN 1 (results/pnr_slice2.md).  qcs2_a / qcs2_b failed global route (GRT-0119):
# horizontal overflow at the left edge, y 2.39-2.7 mm, sources act[] of PE rows 8-10 (as qcs_t6 for rows 11-14): the
# seeded rows drift up by up to ~2 bands in global placement, so their act nets climb along the edge.  Here the pins of
# row r are re-placed into [m(r-1, r), m(r, r+1)], m = midpoint of the placed y-centroids of consecutive PE rows.
source $::QB_DIR/slice_bands.tcl
qb_bands
set blk [ord::get_db_block]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
array set sy {}; array set nn {}; array set ys {}
foreach i [$blk getInsts] {
    if {[regexp {^u_core/g_r_(\d+)__g_c_0__u_pe/} [$i getName] -> r]} {
        lassign [$i getLocation] x y
        lappend ys($r) $y
        set sy($r) [expr {[info exists sy($r)] ? $sy($r) + $y : $y}]
        set nn($r) [expr {[info exists nn($r)] ? $nn($r) + 1 : 1}]
    }
}
set cy {}
for {set r 0} {$r < 16} {incr r} { lappend cy [expr {$sy($r) / double($nn($r)) / $u}] }
set core [$blk getCoreArea]
set ylo [expr {[$core yMin] / double($u)}]; set yhi [expr {[$core yMax] / double($u)}]
for {set r 0} {$r < 16} {incr r} {
    set c [lindex $cy $r]
    set a [expr {$r == 0 ? $c - 60.0 : 0.5 * ($c + [lindex $cy [expr {$r - 1}]])}]
    set b [expr {$r == 15 ? min($yhi - 2.0, $c + 60.0) : 0.5 * ($c + [lindex $cy [expr {$r + 1}]])}]
    if {$b < $a + 40.0} { set b [expr {$a + 40.0}] }
    if {[qb_env QB_REPIN 1] == 2} {
        # QB_REPIN 2: the 15th-85th percentile of row r's placed cell y (regions of different rows may overlap)
        set l [lsort -integer $ys($r)]; set k [llength $l]
        set a [expr {[lindex $l [expr {int(0.15 * $k)}]] / double($u)}]
        set b [expr {[lindex $l [expr {int(0.85 * $k)}]] / double($u)}]
        if {$b < $a + 100.0} { set m [expr {0.5 * ($a + $b)}]; set a [expr {$m - 50.0}]; set b [expr {$m + 50.0}] }
        set a [expr {max($a, $ylo + 2.0)}]; set b [expr {min($b, $yhi - 2.0)}]
    }
    set ::QB_PIN_Y($r) [list $a $b]
    lassign [qb_row_y $r] y0 y1
    qc_log [format "repin row %2d: band %.0f-%.0f  placed centroid %.0f  pins %.0f-%.0f" $r $y0 $y1 $c $a $b]
}
source $::QB_DIR/slice_pins.tcl
estimate_parasitics -placement
qc_summary "repin [join [qc_timing_lines repin] { | }]"
