# impl/r6c QB_ICG (cts_pre.tcl, before clock_tree_synthesis): every integrated clock gate (master CKLNQD*) gets
#   1. a size by its gated-sink count n (QB_ICG_MAP: pairs max_n master; default <=8 D2, <=24 D4, <=64 D8, <=160 D12,
#      else D16) - r6b_b CTS left all 4 006 at CKLNQD1, 46 % with output slew > 0.5 ns;
#   2. QB_ICG_MOVE 1 (default): a location at the centroid of its sinks (r6b_b: ICG output nets > 1 mm on 447 gates,
#      the ICG sat by its enable logic while its flops were spread), legalised by the CTS detailed placement (with
#      QB_SPREAD_ALL: spread3 first, the resized ICGs count as new cells).
# Prints a histogram of n, the masters and the move distance (um).
proc qb6c_icg {} {
    set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
    set map [qb_env QB_ICG_MAP {8 CKLNQD2 24 CKLNQD4 64 CKLNQD8 160 CKLNQD12 1000000000 CKLNQD16}]
    set db [ord::get_db]
    array set nm {}; array set hn {}; set dsum 0.0; set nmv 0; set dmax 0.0; set n0 0
    foreach k {1-8 9-24 25-64 65-160 >160} { set hn($k) 0 }
    foreach i [$blk getInsts] {
        if {![string match CKLNQD* [[$i getMaster] getName]]} continue
        incr n0
        set q [$i findITerm Q]
        if {$q eq "NULL" || [$q getNet] eq "NULL"} continue
        set sx 0.0; set sy 0.0; set n 0
        foreach it [[$q getNet] getITerms] {
            if {[$it getInst] eq $i} continue
            set b [[$it getInst] getBBox]
            set sx [expr {$sx + ([$b xMin] + [$b xMax]) / 2.0}]; set sy [expr {$sy + ([$b yMin] + [$b yMax]) / 2.0}]; incr n
        }
        if {$n == 0} continue
        foreach {mx mn} $map { if {$n <= $mx} break }
        if {$n <= 8} { incr hn(1-8) } elseif {$n <= 24} { incr hn(9-24) } elseif {$n <= 64} { incr hn(25-64) } elseif {$n <= 160} { incr hn(65-160) } else { incr hn(>160) }
        set m [$db findMaster $mn]
        if {$m ne "NULL" && $m ne "" && [[$i getMaster] getName] ne $mn} { $i swapMaster $m }
        set nm($mn) [expr {[info exists nm($mn)] ? $nm($mn) + 1 : 1}]
        if {[qb_env QB_ICG_MOVE 1]} {
            set mm [$i getMaster]
            set cx [expr {round($sx / $n - [$mm getWidth] / 2.0)}]; set cy [expr {round($sy / $n - [$mm getHeight] / 2.0)}]
            lassign [$i getLocation] x y
            set d [expr {(abs($cx - $x) + abs($cy - $y)) / $u}]
            set dsum [expr {$dsum + $d}]; set dmax [expr {max($dmax, $d)}]; incr nmv
            $i setLocation $cx $cy; $i setPlacementStatus PLACED
        }
    }
    set ms {}; foreach k [lsort [array names nm]] { lappend ms $k $nm($k) }
    qc_log [format "r6c: icg %d gates, sinks 1-8 %d 9-24 %d 25-64 %d 65-160 %d >160 %d, masters {%s}, moved %d (mean %.0f um, max %.0f um)" \
        $n0 $hn(1-8) $hn(9-24) $hn(25-64) $hn(65-160) $hn(>160) $ms $nmv [expr {$dsum / max(1, $nmv)}] $dmax]
}
