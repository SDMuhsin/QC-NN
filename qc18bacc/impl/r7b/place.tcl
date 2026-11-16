# PRE_PLACE_TCL of impl/r7b/chip.cfg: impl/r6c/place.tcl (R6b group import, spread3 / snap3, est_rc), blklat.tcl, and
# the group import over QB7_GROUPS [S0 .. S7 SX WA W N] (files <run>/grp_<g>$QB_POS_TAG.pos of impl/r7b/run.sh grp).
source $::QB_R6C/place.tcl
source $::QB_R7B/blklat.tcl
proc qb6_import {} {
    set blk [ord::get_db_block]
    set n 0; set miss 0
    foreach g [qb_env QB7_GROUPS {S0 S1 S2 S3 S4 S5 S6 S7 SX WA W N}] {
        set pf $::OUT/grp_$g[qb_env QB_POS_TAG ""].pos
        if {![file exists $pf]} { qc_log "r7b: no $pf"; continue }
        set f [open $pf]; set k 0
        while {[gets $f l] >= 0} {
            set w [split $l " "]
            set i [$blk findInst [lindex $w 0]]
            if {$i eq "NULL" || $i eq ""} { incr miss; continue }
            if {[llength $w] >= 4} { $i setOrient [lindex $w 3] }
            $i setLocation [lindex $w 1] [lindex $w 2]
            $i setPlacementStatus FIRM
            lappend ::QB6_INSTS $i; incr k
            if {[llength $w] >= 4} { set ::QB6_M($i) [[$i getMaster] getName] }
        }
        close $f
        qc_log "r7b: group $g $k cells imported FIRM"; incr n $k
    }
    set left 0
    foreach i [$blk getInsts] { if {![[$i getMaster] isBlock] && [$i getPlacementStatus] in {NONE UNPLACED}} { incr left } }
    qc_summary "r7b_import cells $n not_found $miss left_for_gpl $left"
    return $left
}
