# R44 (results/r44.md; cts/icg_pre.tcl: qb44_split <gap_um>): before CTS, split every ICG (CKLNQD*) whose gated sinks fall into two groups
# separated by a gap > gap_um in x or y.  The smaller group moves to a clone ICG (same master, same E / TE nets, CP on the
# same clock net), so TritonCTS builds two compact gated trees instead of one H-tree centred between the groups.
proc qb44_split {gap} {
    set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]; set n 0
    foreach i [$blk getInsts] {
        if {![string match CKLNQD* [[$i getMaster] getName]]} continue
        set q [$i findITerm Q]; if {$q eq "NULL" || [$q getNet] eq "NULL"} continue
        set s {}; foreach it [[$q getNet] getITerms] { if {[$it getInst] ne $i} { set b [[$it getInst] getBBox]; lappend s [list $it [expr {[$b xMin]/$u}] [expr {[$b yMin]/$u}]] } }
        if {[llength $s] < 2} continue
        set best 0; set bk 0; set bs {}
        foreach k {1 2} { set ss [lsort -real -index $k $s]
            for {set j 1} {$j < [llength $ss]} {incr j} { set g [expr {[lindex $ss $j $k] - [lindex $ss [expr {$j-1}] $k]}]
                if {$g > $best} { set best $g; set bk $j; set bs $ss } } }
        if {$best <= $gap} continue
        set g1 [lrange $bs 0 [expr {$bk-1}]]; set g2 [lrange $bs $bk end]
        set mv [expr {[llength $g1] <= [llength $g2] ? $g1 : $g2}]
        set cx 0; set cy 0; foreach r $mv { set cx [expr {$cx + [lindex $r 1]}]; set cy [expr {$cy + [lindex $r 2]}] }
        set cx [expr {$cx / [llength $mv]}]; set cy [expr {$cy / [llength $mv]}]
        set c [odb::dbInst_create $blk [$i getMaster] r44_icg_split$n]
        $c setLocation [expr {round($cx*$u)}] [expr {round($cy*$u)}]; $c setPlacementStatus PLACED
        foreach p {E TE CP} { set o [$i findITerm $p]; if {$o ne "NULL" && [$o getNet] ne "NULL"} { [$c findITerm $p] connect [$o getNet] } }
        set qn [odb::dbNet_create $blk r44_icg_split${n}_q]; $qn setSigType CLOCK; [$c findITerm Q] connect $qn
        foreach r $mv { set it [lindex $r 0]; $it disconnect; $it connect $qn }
        qc_log [format "r44: split %s gap %.0f um: %d of %d sinks -> r44_icg_split%d at (%.0f,%.0f)" [$i getName] $best [llength $mv] [llength $s] $n $cx $cy]
        incr n
    }
    qc_log "r44: icg split gap $gap um: $n clones"
}
