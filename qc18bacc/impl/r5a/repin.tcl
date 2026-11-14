# PRE_CTS_TCL of impl/r5a/col.cfg (QB_REPIN 2): act pins of PE row r re-placed into the 15th-85th percentile of row
# r's placed cell y (as impl/pnr/slice_repin.tcl), then impl/r5a/pins.tcl (act_o mirrored again).
# (body in a proc: no global variables leak into later steps, e.g. slice3_post_grt.tcl array w)
proc qb5_repin {} {
    global QB_PIN_Y QB5_DIR QB_DIR
    source $::QB_DIR/slice_bands.tcl
    qb_bands
    set blk [ord::get_db_block]
    set u [[ord::get_db_tech] getDbUnitsPerMicron]
    array set ys {}
    foreach i [$blk getInsts] {
        if {[regexp {^u_core/g_r_(\d+)__g_c_0__u_pe/} [$i getName] -> r]} { lappend ys($r) [lindex [$i getLocation] 1] }
    }
    set core [$blk getCoreArea]
    set ylo [expr {[$core yMin] / double($u)}]; set yhi [expr {[$core yMax] / double($u)}]
    for {set r 0} {$r < 16} {incr r} {
        set l [lsort -integer $ys($r)]; set k [llength $l]
        set a [expr {[lindex $l [expr {int(0.15 * $k)}]] / double($u)}]
        set b [expr {[lindex $l [expr {int(0.85 * $k)}]] / double($u)}]
        if {$b < $a + 100.0} { set m [expr {0.5 * ($a + $b)}]; set a [expr {$m - 50.0}]; set b [expr {$m + 50.0}] }
        set a [expr {max($a, $ylo + 2.0)}]; set b [expr {min($b, $yhi - 2.0)}]
        set ::QB_PIN_Y($r) [list $a $b]
        qc_log [format "r5a repin row %2d: pins %.0f-%.0f" $r $a $b]
    }
    source $::QB5_DIR/pins.tcl
    estimate_parasitics -placement
    qc_summary "repin [join [qc_timing_lines repin] { | }]"
}
qb5_repin
