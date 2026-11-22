# PRE_PLACE_TCL of blocks/act/act.cfg: placement of qb_act2_blk (results/r7c.md, r9a.md, r13.md, r19.md, r20.md).
#   1. S1 cell padding (qb13_pad) and the act output chains at their pins, FIRM during every gpl (place/act_edge.tcl)
#   2. band seed (R19, outermost around global_placement): on the first (non-incremental) call every band cell is put at a
#      random point (seed 19) of its act-row band (x uniform over the core), FIRM while gpl's initial quadratic placement
#      places the other cells around them; then Nesterov with -skip_initial_place and every cell movable (no initial
#      placement that would pull the lb words back to the middle).  The band structure is then held by the netlist itself
#      (lb word -> its band's pre-mux / partials only; cascade to the neighbour bands; s1 registers -> S2 -> act at the
#      row).  Band statistics before / after: summary 'r19 bands'.
#      Band b = act row b: y from the act[288 b .. 288 b + 287] east pins (mean), boundaries at the midpoints between rows,
#      band 0 from 110 um (south strip with the rdq / sdq registers), band 15 to the core top.  Band of a cell (DC names):
#        u_act/u_s1/u_b<b>/*  band b (pre-mux, partial ORs, cascade, s1 registers of home row b)
#        */u_lb/lb_reg_<s>__<bit>_  band pj[bit / 32] (qc18bacc/hw/tb/qb_act2_s1p_pj.txt)   */wer_reg_<b>__<s>_  band b
#        u_act/s1c_r_reg_<b>_  band b
#        R20 QB_ACT_S1T replicas: s1t_c_reg_<k>_ -> band k / 4; selt_reg_<b>__<i>_, sel2t_reg_<b>__<i>_, */shqt_reg_<b>__<i>_ -> b
#   3. the flow's DRV repair (qc_repair_drv) wrapped (R7c): DRV-violating nets by RTL class before the repair
#      (rpt/r7c_drv.txt + summary), repair, incremental global placement at density max(PLACE_DENSITY + 0.06,
#      utilisation after the repair + 0.07) capped at 0.95 (without the re-spread the ~30 k repair buffers are legalised
#      in place and detailed placement sits in diamond search, r7c_A), second DRV repair
source $::QBF/place/act_edge.tcl
qb13_pad
# ---- 3. DRV repair + incremental re-spread + second repair
proc qb7_cls {n} {
    foreach {re c} {{u_lb/} lb {lbf\[} lb_out {u_s1/} s1 {u_s2/} s2 {g_pipe_|actp_|act_q|act\[} act_pipe
                    {sel1|sel2} sel {g_ctx_} ctx_ctl {sdq|s_q} sdq {rdq|m_q} rdq} {
        if {[regexp $re $n]} { return $c }
    }
    return other
}
proc qb7_drv_classes {tag} {
    set blk [ord::get_db_block]
    set rf $::OUT/rpt/r7c_drv.tmp
    qc_to $rf { report_check_types -max_slew -max_capacitance -max_fanout -violators }
    array set v {}; array set c {}
    set f [open $rf]
    while {[gets $f line] >= 0} {
        if {![string match *VIOLATED* $line]} { continue }
        set pin [lindex $line 0]; set k [string last / $pin]
        set it NULL
        if {$k < 0} { set it [$blk findBTerm $pin] } elseif {[set i [$blk findInst [string range $pin 0 [expr {$k - 1}]]]] ne "NULL"} {
            set it [$i findITerm [string range $pin [expr {$k + 1}] end]] }
        if {$it ne "NULL" && [$it getNet] ne "NULL"} { set v([[$it getNet] getName]) 1 }
    }
    close $f; file delete $rf
    foreach n [array names v] { incr c([qb7_cls $n]) }
    set s "$tag drv_nets [array size v]:"
    foreach k [lsort [array names c]] { append s " $k $c($k)" }
    set fh [open $::OUT/rpt/r7c_drv.txt a]; puts $fh "$s [qc_util]"; close $fh
    qc_summary $s
}
if {[info commands qb_drv_orig] eq ""} {
    rename qc_repair_drv qb_drv_orig
    proc qc_repair_drv {} {
        qb7_drv_classes before_repair1
        qb_drv_orig
        qc_summary "r7c after_repair1 [qc_util]"
        regexp {utilisation ([0-9.]+)} [qc_util] -> u
        set dens [expr {min(0.95, max([p PLACE_DENSITY] + 0.06, $u + 0.07))}]
        qc_log "gpl_incr2: incremental global placement after the DRV repair, density $dens [qc_util]"
        global_placement -incremental -density $dens -pad_left [p PLACE_PAD] -pad_right [p PLACE_PAD] {*}[p GPL_ARGS]
        estimate_parasitics -placement
        qb7_drv_classes before_repair2
        qb_drv_orig
        qc_summary "r7c after_repair2 [qc_util]"
    }
}
# ---- 2. act-row bands
proc qb19_pj {} {
    set f [open [file normalize $::QBF/../hw/tb/qb_act2_s1p_pj.txt]]
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
    set lo [expr {max([$core yMin], round(110 * $u))}]
    set B {}
    for {set r 0} {$r < 16} {incr r} {
        set a [expr {$r == 0 ? $lo : round(([lindex $ys [expr {$r - 1}]] + [lindex $ys $r]) / 2)}]
        set b [expr {$r == 15 ? [$core yMax] : round(([lindex $ys $r] + [lindex $ys [expr {$r + 1}]]) / 2)}]
        lappend B [list $a $b [lindex $ys $r]]
    }
    return $B
}
proc qb19_band_of {n pj} {
    if {[regexp {s1t_c_reg_(\d+)_} $n -> k]} { return [expr {$k / 4}] }
    if {[regexp {(?:selt|sel2t|shqt)_reg_(\d+)__\d+_} $n -> b]} { return $b }
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
if {[info commands qb19_gpl_orig] eq ""} {
    rename global_placement qb19_gpl_orig
    proc global_placement {args} {
        if {[lsearch $args -incremental] < 0 && ![info exists ::QB19_DONE]} {
            set ::QB19_DONE 1
            set blk [ord::get_db_block]; set core [$blk getCoreArea]
            set pj [qb19_pj]; set B [qb19_bands]
            expr {srand(19)}
            set k 0; set seeded {}
            set bh 1.0
            foreach i [$blk getInsts] {
                if {[$i getPlacementStatus] in {FIRM LOCKED COVER}} { continue }
                set b [qb19_band_of [$i getName] $pj]
                if {$b < 0} { continue }
                lassign [lindex $B $b] a c yc
                set h [expr {($c - $a) * $bh}]
                set x [expr {[$core xMin] + int(rand() * ([$core dx] - [[$i getMaster] getWidth]))}]
                set y [expr {int($yc - $h / 2 + rand() * $h)}]
                set y [expr {min(max($y, [$core yMin]), [$core yMax] - [[$i getMaster] getHeight])}]
                $i setLocation $x $y; $i setPlacementStatus FIRM
                lappend seeded $i
                incr k
            }
            qc_summary "r19 band seed cells $k bands [llength $B] y0_um [expr {[lindex $B 0 0] / double([[ord::get_db_tech] getDbUnitsPerMicron])}]"
            qb19_stats seed
            # initial (quadratic) placement of the other cells with the band cells as fixed anchors, then Nesterov
            # from there with every cell movable
            qb19_gpl_orig {*}$args -skip_nesterov_place
            foreach i $seeded { $i setPlacementStatus PLACED }
            qb19_gpl_orig {*}$args -skip_initial_place
            qb19_stats gpl
            return
        }
        qb19_gpl_orig {*}$args
    }
}
