# PRE_CTS_TCL of blocks/hub/hub.cfg (results/r33.md, r34.md, r9b.md); one file for impl/r34/cts_pre -> r9b/cts_pre:
#   1. (R33 defect 2) collapse the clumped repeater pairs that the place step's incremental global placements leave
#      behind: a buffer b1 whose output net has one load, a buffer b2 within 10 um -> b1 is removed and its input net
#      drives b2 (run on db/place.odb before CTS)
#   2. (R33 defect 3) repair_clock_nets with BUFF* / INV* dont_use, so the clock nets get CK cells only
#   3. ICG split (gap QB44_SPLIT [400] um) + sizing by gated-sink count + move to the sink centroid (cts/icg_pre.tcl),
#      legalised by the CTS step's detailed placement
proc qb34_isbuf {m} { return [regexp {^(BUFF|CKBD)} [$m getName]] }
proc qb34_census {tag} {
    set nb 0; set ab 0.0; set a 0.0; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    foreach i [[ord::get_db_block] getInsts] {
        set m [$i getMaster]; if {[$m isBlock]} continue
        set x [expr {[$m getWidth] * [$m getHeight]}]; set a [expr {$a + $x}]
        if {[qb34_isbuf $m]} { incr nb; set ab [expr {$ab + $x}] }
    }
    qc_log [format "r34: %s buffers %d (%.0f um2) std_um2 %.0f" $tag $nb [expr {$ab / $u / $u}] [expr {$a / $u / $u}]]
}
proc qb34_pairs {} {
    set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]; set out {}
    set dmax 10
    foreach i [$blk getInsts] {
        set m [$i getMaster]; if {![qb34_isbuf $m] || [$i isDoNotTouch]} continue
        set o [$i findITerm Z]; set ii [$i findITerm I]; if {$o eq "NULL" || $ii eq "NULL"} continue
        set n [$o getNet]; set ni [$ii getNet]
        if {$n eq "NULL" || $ni eq "NULL" || [$n getSigType] ne "SIGNAL" || [$ni getSigType] ne "SIGNAL"} continue
        if {[llength [$n getBTerms]] || [$n isDoNotTouch]} continue
        set s {}; foreach it [$n getITerms] { if {[$it isInputSignal]} { lappend s $it } }
        if {[llength $s] != 1} continue
        set b2 [[lindex $s 0] getInst]; if {![qb34_isbuf [$b2 getMaster]]} continue
        lassign [$i getLocation] x1 y1; lassign [$b2 getLocation] x2 y2
        if {(abs($x1 - $x2) + abs($y1 - $y2)) / $u < $dmax} { lappend out $i }
    }
    return $out
}
# (a proc: the flow's step loop variable is the global 's', flow.tcl saves db/<s>.odb after this step)
proc qb34_collapse {} {
    set t [clock seconds]; qb34_census coll_pre; set tot 0
    for {set it 0} {$it < 6} {incr it} {
        set ps [qb34_pairs]; if {![llength $ps]} break
        set k 0
        foreach b1 $ps {
            set in [[$b1 findITerm I] getNet]; set o [[$b1 findITerm Z] getNet]
            if {$in eq "NULL" || $o eq "NULL"} continue
            set s {}; foreach x [$o getITerms] { if {[$x isInputSignal]} { lappend s $x } }
            if {[llength $s] != 1} continue
            set b2it [lindex $s 0]
            $b2it disconnect; [$b1 findITerm I] disconnect; [$b1 findITerm Z] disconnect
            $b2it connect $in
            odb::dbInst_destroy $b1
            if {[llength [$o getITerms]] == 0} { odb::dbNet_destroy $o }
            incr k
        }
        incr tot $k; qc_log "r34: collapse pass $it removed $k"
    }
    qb34_census coll_post; qc_log "r34: collapsed $tot clumped repeaters ([expr {[clock seconds] - $t}] s)"
}
qb34_collapse
if {[info commands qb34_rcn_orig] eq ""} {
    rename repair_clock_nets qb34_rcn_orig
    proc repair_clock_nets {args} {
        set c [get_lib_cells {BUFF* INV*}]
        set_dont_use $c
        qb34_rcn_orig {*}$args
        unset_dont_use $c; set_dont_use $::QC_DONT_USE
        qc_log "r34: repair_clock_nets with BUFF* / INV* dont_use (CK cells only)"
    }
}
source $::QBF/cts/icg_pre.tcl
