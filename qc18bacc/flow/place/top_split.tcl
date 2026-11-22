# Sourced by place/top_place.tcl (results/r14.md 3, r39.md): channel-end repeaters for top nets that must cross a hard block (results/r14.md 3).
# Mechanism (R11 + r14_d): repair_design buffers a long net along its Steiner tree with the M3 estimate RC
# (QC_PNR_EST_SIGNAL); when the tree crosses the act block (gap <-> north band) or the array (hub pins on the
# hub / column seam <-> column north pins / band), the repeaters land inside a block footprint (no rows): DPL moves
# them up to 1.5 mm (diamond search, R11 r11_b > 1.5 h) or fails (r14_d: DPL-0036 on 2 "wire" buffers > 1 000 um
# from any site).  Fix: after global placement, every top net whose terminals sit on more than one side of the
# blocks -- G (gap: x < X0, y < act bottom; chip IOs, hub west-strip pins, act south pins), N (north: y >= array top;
# band, NW corner, column north pins, weights), M (block pins on the hub / column seam, x >= X0) -- is split:
#   driver-side launch buffer L (BUFFD16; none if the driver is a seam block pin), one receiver buffer R_s
#   (BUFFD4) per other G / N side at that side's block edge, seam pins stay on the trunk;
#   trunk = {L.Z | driver, R_s.I, seam pins}: the over-block segment, routed on M8 / M9, dont_touch for the
#   placement-parasitics repair and checked at GRT parasitics (route/top_drv_post.tcl).
# L / R are FIXED on free row positions next to the block edge facing the trunk (G: rows under the act block's
# south edge; N: band rows just above the array / act top).  Side nets keep normal repair.
proc q14s_side {x y} {
    if {$x < $::QB14_X0 && $y < [lindex $::QB11_ACT 1] + 1.0} { return G }
    if {$y >= $::QB11_YT - 1.0} { return N }
    if {abs($y - $::QB11_YH) < 2.5 && $x >= $::QB14_X0 - 1.0} { return M }
    return X
}
proc q14s_release {} {
    foreach i [[ord::get_db_block] getInsts] { if {[string match q14s_* [$i getName]]} { $i setPlacementStatus PLACED } }
}
proc q14s_split {} {
    set b [ord::get_db_block]; set u [$b getDefUnits]; set db [ord::get_db]
    set mL [$db findMaster BUFFD16]; set mR [$db findMaster BUFFD4]
    set ya [lindex $::QB11_ACT 1]; set yt $::QB11_YT
    set blocks {qb_col_blk qb_hub qb_act2_blk}
    set cknet [[$b findBTerm clk] getNet]
    array set occ {}; set nblk 0; set nsplit 0; set nbuf 0; set trunks {}; array set kinds {}
    # position slot allocator: rows next to the edge, x stepped 6 um on collision
    proc q14s_slot {side x} {
        upvar occ occ
        set x [expr {min(max($x, 10.0), ($side eq "G" ? $::QB14_X0 - 12.0 : [lindex $::QB14_DIE 0] - 12.0))}]
        # 16-um x buckets, every 2nd row, 120 rows next to the block edge first, then neighbouring buckets (R39 slot
        # spreading; R14 had 8 um / every row / 40 rows: the FIRM L / R buffer arrays at the channel ends were the densest
        # bins, 0.9, on r39_y)
        set sx 16; set rs 2; set rn 120
        set b0 [expr {int(round($x / $sx))}]
        for {set k 0} {$k < 80} {incr k} {
            set bk [expr {$b0 + (($k % 2) ? -1 : 1) * (($k + 1) / 2)}]
            set xx [expr {$bk * $sx}]
            if {$xx < 10.0 || $xx > ($side eq "G" ? $::QB14_X0 - 12.0 : [lindex $::QB14_DIE 0] - 12.0)} { continue }
            for {set r 2} {$r < $rn} {incr r $rs} {
                set y [expr {$side eq "G" ? floor([lindex $::QB11_ACT 1] / 1.8) * 1.8 - 1.8 * ($r + 1) : ceil($::QB11_YT / 1.8) * 1.8 + 1.8 * $r}]
                set key "$side,$bk,$r"
                if {![info exists occ($key)]} { set occ($key) 1; return [list $xx $y] }
            }
        }
        return [list $x [expr {$side eq "G" ? floor([lindex $::QB11_ACT 1] / 1.8) * 1.8 - 3.6 : ceil($::QB11_YT / 1.8) * 1.8 + 3.6}]]
    }
    # two passes: collect the gap <-> north crossings first and give them crossing x evenly spread over the act block
    # width (by rank of the driver x): r14_j3 put every trunk at its driver's x -> 500 trunks within +-200 um of the
    # sequencer centre, 12 % of the gcells over the act block overflowed
    array set xcmap {}; set cand {}
    foreach pass {collect do} {
    if {$pass eq "do"} {
        set cand [lsort -real -index 1 $cand]; set nc [llength $cand]
        # R39: crossing x spread over the west std-cell channel 10 .. 10 + 680 um of the floorplan (trunks run through the
        # channel's rows / all layers instead of over the act's M8): the first 90 % of the crossings (by driver x) over the
        # channel, the rest (10 %) over the act 10+680+20 .. X0-12 (capacity split: the act exposes ~2 V tracks per gcell)
        set w 680
        if {$nc > 0} {
            set nch [expr {int(round((1.0 - 0.1) * $nc))}]; set x1 [expr {10.0 + $w + 20.0}]; set wa [expr {$::QB14_X0 - 12.0 - $x1}]
            for {set k 0} {$k < $nc} {incr k} {
                set xcmap([lindex $cand $k 0]) [expr {$k < $nch ? 10.0 + ($k + 0.5) * $w / max($nch, 1) : $x1 + ($k - $nch + 0.5) * $wa / max($nc - $nch, 1)}]
            }
        }
    }
    foreach net [$b getNets] {
        if {[$net getSigType] ne "SIGNAL" || [$net isSpecial]} { continue }
        if {$net eq $cknet} { continue }
        set its [$net getITerms]; set bts [$net getBTerms]
        if {[llength $its] + [llength $bts] < 2} { continue }
        set drv ""; set dside ""; array unset T; array set T {}; set allblk 1
        foreach t $its {
            set i [$t getInst]; set m [[$i getMaster] getName]
            set isb [expr {[lsearch -exact $blocks $m] >= 0}]
            if {!$isb} { set allblk 0 }
            if {$isb} {
                lassign [$t getAvgXY] ok x y
                if {!$ok} { continue }
            } else {
                set bb [$i getBBox]; set x [expr {([$bb xMin] + [$bb xMax]) / 2}]; set y [expr {([$bb yMin] + [$bb yMax]) / 2}]
            }
            set x [expr {$x / double($u)}]; set y [expr {$y / double($u)}]
            set s [q14s_side $x $y]
            if {$s eq "X"} { if {$isb} { set s M } elseif {$x < $::QB14_X0 && $y < $ya} { set s G } else { set s N } }
            if {[$t isOutputSignal] && [string match CKLN* $m]} { set drv CLK; break }
            if {[$t isOutputSignal]} { set drv $t; set dside $s; set dx $x; set dy $y; set dblk $isb }
            lappend T($s) [list $t $x $y $isb]
        }
        foreach t $bts { set allblk 0; lappend T(G) [list $t 0 0 0]; if {[$t getIoType] eq "INPUT"} { set drv $t; set dside G; set dx 0; set dy 0; set dblk 0 } }
        if {$drv eq "" || $drv eq "CLK"} { continue }
        set sides [array names T]
        if {[llength $sides] < 2} { continue }
        if {[llength $sides] == 2 && [lsearch $sides M] >= 0 && [llength $T(M)] == 0} { continue }
        if {$pass eq "collect"} { if {$dside ne "M"} { lappend cand [list [$net getName] $dx] }; continue }
        # split (block-only multi-side nets too, e.g. hub -> 8 column north ctl pins: the band part has rows; they were
        # dont_touch'd by place/top_place.tcl as block-only -> released here, the trunk gets it back)
        incr nsplit; set nm [$net getName]
        if {$allblk} { unset_dont_touch [get_nets $nm]; incr nblk }
        set trunk [odb::dbNet_create $b q14s_t$nsplit]
        set k "[join [lsort $sides] {}]:$dside"; incr kinds($k)
        # driver side
        if {$dside eq "M" || ($dblk && $dside eq "M")} {
            # seam block pin drives the trunk directly; other seam pins too
            foreach e $T(M) { [lindex $e 0] disconnect; [lindex $e 0] connect $trunk }
        } else {
            # trunk endpoints at one x (the crossing x): over the act block for gap <-> north, so the trunk is the
            # straight vertical over-block segment and every horizontal run stays in a side net (rows, repaired)
            set xc [expr {[info exists xcmap($nm)] ? $xcmap($nm) : min(max($dx, 10.0), $::QB14_X0 - 12.0)}]
            lassign [q14s_slot $dside $xc] lx ly
            set L [odb::dbInst_create $b $mL q14s_L$nsplit]; incr nbuf
            $L setLocation [expr {int($lx * $u)}] [expr {int($ly * $u)}]; $L setPlacementStatus FIRM
            [$L findITerm I] connect $net; [$L findITerm Z] connect $trunk
            if {[info exists T(M)]} { foreach e $T(M) { [lindex $e 0] disconnect; [lindex $e 0] connect $trunk } }
        }
        foreach s {G N} {
            if {$s eq $dside || ![info exists T($s)]} { continue }
            if {$dside eq "M"} { set sx [expr {$s eq "G" ? min(max($dx, 10.0), $::QB14_X0 - 12.0) : $dx}] } else { set sx $xc }
            lassign [q14s_slot $s $sx] rx ry
            set R [odb::dbInst_create $b $mR q14s_R${s}$nsplit]; incr nbuf
            $R setLocation [expr {int($rx * $u)}] [expr {int($ry * $u)}]; $R setPlacementStatus FIRM
            set sn [odb::dbNet_create $b q14s_${s}$nsplit]
            foreach e $T($s) {
                set t [lindex $e 0]
                if {[string match *dbBTerm* $t] || [catch {$t getInst}]} { $t disconnect; $t connect $sn } else { $t disconnect; $t connect $sn }
            }
            [$R findITerm I] connect $trunk; [$R findITerm Z] connect $sn
        }
        # a seam-driven net whose driver side had other (G / N) terminals is handled above; empty original net is fine
        lappend trunks q14s_t$nsplit
    }
    }
    if {[llength $trunks]} { set_dont_touch [get_nets $trunks] }
    set f [open $::OUT/rpt/split14.txt w]
    puts $f "# R14 split14: $nsplit block-crossing nets split ($nblk block-only), $nbuf channel-end buffers (FIRM), trunks dont_touch"
    foreach k [lsort [array names kinds]] { puts $f [format "%-12s %6d" $k $kinds($k)] }
    close $f
    qc_log "r14 split14: $nsplit block-crossing nets split ($nblk block-only; [join [lmap k [lsort [array names kinds]] {format %s=%d $k $kinds($k)}] {, }]), $nbuf channel-end buffers"
}
