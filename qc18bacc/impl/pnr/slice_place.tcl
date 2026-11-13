# PRE_PLACE_TCL of slice.cfg: band placement guides for the column strip (results/pnr_slice.md).
# This OpenROAD build's global placement ignores region fences (dbRegion / dbGroup and create_voltage_domain groups
# were tested on the 8 x 2 proxy: 0 of 6 131 member cells inside the box after gpl), so the bands of
# slice_bands.tcl are imposed as a seed: every cell starts at a random point in a small box at the centre of its band
# (PE row r: row r's band; lanes, parameter banks and top glue: lane band; broadcast register of group g: centre of
# rows 8g .. 8g + 7; decoders: between the groups), then global placement runs from that seed with
# -skip_initial_place (P(GPL_ARGS) of slice.cfg) and timing-driven net weighting.  Afterwards the band adherence of
# every class is logged (fraction of its cells whose y lies in its band +- 0.5 band).
source $::QB_DIR/slice_bands.tcl
qb_bands
set blk [ord::get_db_block]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
expr {srand(908)}
set xc [expr {($::QB_X0 + $::QB_X1) / 2.0}]
set wx [expr {0.15 * ($::QB_X1 - $::QB_X0)}]
proc qb_target {c} {
    switch -glob -- $c {
        pe*   { lassign [qb_row_y [string range $c 2 end]] a b; return [list [expr {($a + $b) / 2.0}] [expr {0.15 * $::QB_HP}]] }
        br*   { set g [string range $c 2 end]; lassign [qb_row_y [expr {8 * $g + 3}]] a b; return [list $b [expr {0.15 * $::QB_HP}]] }
        dec   { lassign [qb_row_y 7] a b; return [list $b [expr {0.15 * $::QB_HP}]] }
        default { return [list [expr {$::QB_Y0 + $::QB_HL / 2.0}] [expr {0.15 * $::QB_HL}]] }
    }
}
array set cnt {}
foreach i [$blk getInsts] {
    if {![[$i getMaster] isCore] || [$i isFixed]} { continue }
    set c [qb_class [$i getName]]
    lassign [qb_target $c] yc wy
    set x [expr {$xc + (rand() - 0.5) * 2 * $wx}]
    set y [expr {$yc + (rand() - 0.5) * 2 * $wy}]
    $i setLocation [expr {int($x * $u)}] [expr {int($y * $u)}]
    $i setPlacementStatus PLACED
    incr cnt($c)
}
qc_log "slice seed: [lmap k [lsort [array names cnt]] {string cat $k = $cnt($k)}]"
# band adherence after global placement (wraps global_placement once)
rename global_placement qb_gpl_orig
proc global_placement {args} {
    qb_gpl_orig {*}$args
    rename global_placement {}
    rename qb_gpl_orig global_placement
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    array set in {}; array set all {}
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isCore]} { continue }
        set c [qb_class [$i getName]]
        set y [expr {([lindex [$i getLocation] 1] + [[$i getMaster] getHeight] / 2.0) / $u}]
        switch -glob -- $c {
            pe*  { lassign [qb_row_y [string range $c 2 end]] a b; set ok [expr {$y >= $a - 0.5 * $::QB_HP && $y <= $b + 0.5 * $::QB_HP}] }
            lane { set ok [expr {$y <= $::QB_Y0 + 1.1 * $::QB_HL}] }
            default { set ok 1 }
        }
        incr all($c); if {$ok} { incr in($c) }
    }
    set s {}
    foreach c [lsort -dictionary [array names all]] { if {![info exists in($c)]} { set in($c) 0 }; lappend s "$c [format %.3f [expr {$in($c) / double($all($c))}]]" }
    qc_log "slice band adherence after gpl: [join $s {, }]"
    if {[qb_env QB_COMPACT 0]} {
        qb_compact_lanes
        # legalise before the DRV repair (qcs_t3 without this: the repair sized the compacted, overlapping lanes,
        # legalisation then added 41 % HPWL and left long unrepaired nets, place WNS -6.5 ns)
        set t [clock seconds]
        detailed_placement {*}[p DPL_ARGS]
        qc_log "slice compact: legalised before the DRV repair ([expr {[clock seconds] - $t}] s)"
    }
}
# QB_COMPACT 1 (in place) / 2 (slots, below): after global placement, each lane (32 fused, 4 wide) is compressed around its own area-weighted
# centroid into a block of its cell area / QB_COMPACT_UTIL (default 0.65), x and y scaled separately (a uniform
# spread over the block side has rms side / sqrt(12)); cells never move away from the centroid.  Why
# (results/pnr_slice.md): the timing-driven global placement still stretches a fused lane along the lane band
# between the PE shadow (top of the band) and its stream pins (bottom edge), qcs_w1: lane g_fi_6 of row 1 spans
# 840 um inside u_fin (u_rlate -> u_rout) and the DRV repair buffers that net with a 49-buffer chain (~1.4 ns).  A
# compact lane moves the distance onto its registered boundary nets (PE shadow -> lane input register, stream pins).
proc qb_compact_lanes {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set ut [qb_env QB_COMPACT_UTIL 0.65]
    set mode [qb_env QB_COMPACT 1]
    array set mem {}
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isCore]} { continue }
        if {[regexp {^(u_core/g_fq_\d+__g_fc_0__g_fi_\d+__u_lf|u_core/g_wq_\d+__g_wc_0__u_lw)/} [$i getName] -> k]} { lappend mem($k) $i }
    }
    set n 0; set srms 0.0; set lanes {}
    foreach k [array names mem] {
        set A 0.0; set sx 0.0; set sy 0.0
        foreach i $mem($k) {
            set m [$i getMaster]; set a [expr {[$m getWidth] * double([$m getHeight])}]
            lassign [$i getLocation] x y
            set A [expr {$A + $a}]; set sx [expr {$sx + $a * ($x + [$m getWidth] / 2.0)}]; set sy [expr {$sy + $a * ($y + [$m getHeight] / 2.0)}]
        }
        set cx [expr {$sx / $A}]; set cy [expr {$sy / $A}]
        set vx 0.0; set vy 0.0
        foreach i $mem($k) {
            set m [$i getMaster]; set a [expr {[$m getWidth] * double([$m getHeight])}]
            lassign [$i getLocation] x y
            set vx [expr {$vx + $a * pow($x + [$m getWidth] / 2.0 - $cx, 2)}]; set vy [expr {$vy + $a * pow($y + [$m getHeight] / 2.0 - $cy, 2)}]
        }
        lappend lanes [list $k $cx $cy [expr {sqrt($vx / $A)}] [expr {sqrt($vy / $A)}] $A]
    }
    # mode 2: non-overlapping slots, a grid of QB_SLOT_COLS columns over the lane band, lanes assigned in the order of
    # their gpl centroids (rows by y, then x within a row); block = slot size x 0.9
    if {$mode == 2} {
        set nc [qb_env QB_SLOT_COLS 3]
        set nr [expr {int(ceil([llength $lanes] / double($nc)))}]
        set sw [expr {($::QB_X1 - $::QB_X0) / $nc * $u}]; set sh [expr {$::QB_HL / $nr * $u}]
        set byy [lsort -real -index 2 $lanes]; set out {}
        for {set r 0} {$r < $nr} {incr r} {
            set row [lsort -real -index 1 [lrange $byy [expr {$r * $nc}] [expr {$r * $nc + $nc - 1}]]]
            for {set c 0} {$c < [llength $row]} {incr c} {
                lassign [lindex $row $c] k cx cy rx ry A
                lappend out [list $k $cx $cy $rx $ry $A [expr {$::QB_X0 * $u + ($c + 0.5) * $sw}] [expr {$::QB_Y0 * $u + ($r + 0.5) * $sh}] [expr {0.9 * $sw}] [expr {0.9 * $sh}]]
            }
        }
        set lanes $out
    } else {
        set out {}
        foreach l $lanes { lassign $l k cx cy rx ry A; set sd [expr {sqrt($A / $ut)}]; lappend out [list $k $cx $cy $rx $ry $A $cx $cy $sd $sd] }
        set lanes $out
    }
    foreach l $lanes {
        lassign $l k cx cy rx ry A tx ty bw bh
        set kx [expr {min(1.0, $bw / sqrt(12.0) / max($rx, 1.0))}]
        set ky [expr {min(1.0, $bh / sqrt(12.0) / max($ry, 1.0))}]
        foreach i $mem($k) {
            set m [$i getMaster]
            lassign [$i getLocation] x y
            set nx [expr {$tx + ($x + [$m getWidth] / 2.0 - $cx) * $kx - [$m getWidth] / 2.0}]
            set ny [expr {$ty + ($y + [$m getHeight] / 2.0 - $cy) * $ky - [$m getHeight] / 2.0}]
            $i setLocation [expr {int($nx)}] [expr {int($ny)}]
        }
        incr n
        set srms [expr {$srms + max($rx, $ry) / $u}]
        qc_log [format "slice compact %s cells %d centroid (%.0f, %.0f) um rms (%.0f, %.0f) um -> block %.0f x %.0f um at (%.0f, %.0f)" $k \
            [llength $mem($k)] [expr {$cx / $u}] [expr {$cy / $u}] [expr {$rx / $u}] [expr {$ry / $u}] [expr {$bw / $u}] [expr {$bh / $u}] \
            [expr {$tx / $u}] [expr {$ty / $u}]]
    }
    qc_log [format "slice compact (mode %d): %d lanes, mean max-axis rms before %.0f um" $mode $n [expr {$srms / max($n, 1)}]]
}
