# R19 (results/r19.md): act-row bands of the QB_ACT_S1P qb_act2_blk (sourced by impl/r19/place.tcl and stats.tcl).
# Band b = act row b: y from the act[288 b .. 288 b + 287] east pins (mean), boundaries at the midpoints between rows,
# band 0 from QB19_YLO um (default 110: south strip with the rdq / sdq registers), band 15 to the core top.
# Band of a cell (by name; DC change_names forms):
#   u_act/u_s1/u_b<b>/*                    band b   (pre-mux, partial ORs, cascade, s1 registers of home row b)
#   */u_lb/lb_reg_<s>__<bit>_              band pj[bit / 32]   (both contexts)
#   */wer_reg_<b>__<s>_                    band b
#   u_act/s1c_r_reg_<b>_                   band b
proc qb19_pj {} {
    set f [open [file normalize $::QB19_DIR/../../hw/tb/qb_act2_s1p_pj.txt]]
    set pj {}
    while {[gets $f l] >= 0} { if {[regexp {^(\d+) (\d+)$} $l -> j b]} { dict set pj $j $b } }
    close $f
    return $pj
}
proc qb19_bands {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set core [$blk getCoreArea]
    array set sy {}; array set sn {}
    foreach bt [$blk getBTerms] {
        if {![regexp {^act\[(\d+)\]$} [$bt getName] -> k]} { continue }
        set r [expr {$k / 288}]
        set bx [lindex [[lindex [$bt getBPins] 0] getBoxes] 0]
        set y [expr {([$bx yMin] + [$bx yMax]) / 2.0}]
        if {[info exists sy($r)]} { set sy($r) [expr {$sy($r) + $y}]; incr sn($r) } else { set sy($r) $y; set sn($r) 1 }
    }
    set ys {}
    for {set r 0} {$r < 16} {incr r} { lappend ys [expr {$sy($r) / $sn($r)}] }
    set lo [expr {max([$core yMin], round([qb_env QB19_YLO 110] * $u))}]
    set B {}
    for {set r 0} {$r < 16} {incr r} {
        set a [expr {$r == 0 ? $lo : round(([lindex $ys [expr {$r - 1}]] + [lindex $ys $r]) / 2)}]
        set b [expr {$r == 15 ? [$core yMax] : round(([lindex $ys $r] + [lindex $ys [expr {$r + 1}]]) / 2)}]
        lappend B [list $a $b [lindex $ys $r]]
    }
    return $B
}
proc qb19_band_of {n pj} {
    if {[regexp {u_s1/u_b(\d+)/} $n -> b]} { return $b }
    if {[regexp {u_lb/lb_reg_(\d+)__(\d+)_} $n -> s bit]} { return [dict get $pj [expr {$bit / 32}]] }
    if {[regexp {wer_reg_(\d+)__(\d+)_} $n -> b s]} { return $b }
    if {[regexp {s1c_r_reg_(\d+)_} $n -> b]} { return $b }
    return -1
}
# per-band y statistics of the band cells: n, share inside own band, |dy| from the band centre p50 / p90 (um)
proc qb19_stats {tag} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set pj [qb19_pj]; set B [qb19_bands]
    array set n {}; array set inb {}; array set dy {}
    foreach i [$blk getInsts] {
        set b [qb19_band_of [$i getName] $pj]
        if {$b < 0} { continue }
        set cls [expr {[string match *u_lb/* [$i getName]] ? "lb" : [string match *u_s1/* [$i getName]] ? "s1" : "en"}]
        lassign [$i getLocation] x y
        lassign [lindex $B $b] a c yc
        incr n($cls); if {$y >= $a && $y < $c} { incr inb($cls) }
        lappend dy($cls) [expr {abs($y - $yc) / double($u)}]
    }
    set s "r19 bands $tag"
    foreach cls [lsort [array names n]] {
        set d [lsort -real $dy($cls)]; set m [llength $d]
        append s [format " | %s n %d in_band %.3f dy_p50 %.0f dy_p90 %.0f" $cls $n($cls) \
            [expr {[info exists inb($cls)] ? $inb($cls) / double($n($cls)) : 0}] [lindex $d [expr {$m / 2}]] [lindex $d [expr {$m * 9 / 10}]]]
    }
    qc_summary $s
}
