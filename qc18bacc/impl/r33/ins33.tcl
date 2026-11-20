# R33 PRE_PLACE_TCL: the production hook (impl/r21/place_pre.tcl) + a repeater-adjacency census after every
# global_placement / repair_design / detailed_placement of the place step (R33C lines in openroad.log)
source /tmp/ckp908/qc18bacc/r31_snap4/qc18bacc/impl/r21/place_pre.tcl
proc r33_isbuf {m} { return [regexp {^(BUFF|CKBD)} [$m getName]] }
proc r33_census {tag} {
    set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
    set nb 0; set ab 0.0; set np 0; set dl {}
    foreach i [$blk getInsts] {
        set m [$i getMaster]; if {![r33_isbuf $m]} continue
        incr nb; set ab [expr {$ab + [$m getWidth] * [$m getHeight] / $u / $u}]
        set o [$i findITerm Z]; if {$o eq "NULL"} continue
        set n [$o getNet]; if {$n eq "NULL" || [$n getSigType] ne "SIGNAL" || [llength [$n getBTerms]]} continue
        set s {}; foreach it [$n getITerms] { if {[$it isInputSignal]} { lappend s $it } }
        if {[llength $s] != 1} continue
        set b [[lindex $s 0] getInst]; if {![r33_isbuf [$b getMaster]]} continue
        lassign [$i getLocation] x1 y1; lassign [$b getLocation] x2 y2
        set d [expr {(abs($x1 - $x2) + abs($y1 - $y2)) / $u}]; lappend dl $d
        if {$d < 10.0} { incr np }
    }
    set dl [lsort -real $dl]; set k [llength $dl]
    set ws NA; catch { set ws [format %.3f [expr {[sta::worst_slack_cmd max] * 1e9}]] }
    qc_log [format "R33C %-28s buffers %6d (%.0f um2) buf->buf nets %6d p10 %.1f p50 %.1f um, adjacent (<10 um) %6d | wns %s" \
        $tag $nb $ab $k [expr {$k ? [lindex $dl [expr {$k / 10}]] : 0}] [expr {$k ? [lindex $dl [expr {$k / 2}]] : 0}] $np $ws]
}
rename global_placement r33_gpl_orig
proc global_placement {args} { r33_gpl_orig {*}$args; estimate_parasitics -placement; r33_census "gpl[incr ::r33_g] [expr {[lsearch $args -incremental] >= 0 ? {incr} : {full}}]" }
rename repair_design r33_rd_orig
proc repair_design {args} { r33_rd_orig {*}$args; r33_census "repair_design[incr ::r33_r]" }
rename detailed_placement r33_dpl_orig
proc detailed_placement {args} { r33_dpl_orig {*}$args; estimate_parasitics -placement; r33_census "dpl[incr ::r33_d]" }
