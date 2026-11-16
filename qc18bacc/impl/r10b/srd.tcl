# R10b S-read placement (sourced by impl/r10b/place_pre.tcl, QB10_SRD 1): the combinational cone of the act-port
# S read (S macro Q -> group mux -> 2048-b lane rotator -> hub ports u_top_s_q[*], qb_top.sv g_srot) is placed by
# structure before global placement and kept FIRM through gpl / DRV repair / incremental gpl (set PLACED again just
# before the place step's detailed placement):
#   column-local cells (every source S macro in one column; the group mux and any same-column rotator stage):
#       in the macro-row channel nearest to the mean Q-pin y of their sources, x at their sources' centre
#       -> the 2048 westward wires start inside the S macro rows, whose M5 / M7 / M9 are free over the macros
#   multi-column cells (rotator body): in the north-west corner region QB10_RX0..QB10_RX1 x QB10_RY0..die top - 8,
#       one band per logic level (level 0 = drives a port, top), x = mean x of the s_q pins the cell reaches
#       (s_q pins fixed j-major by impl/r10b/pins10.tcl, so one 16-word bit slice j is a 6.4-um wide strip)
# Packing: shelf packing per band, cell pitch = width / QB10_SDENS [0.5], legal sites (row grid), no overlaps.
# Report: <run>/rpt/srd.txt (cone size per class, sources, levels).
proc qb10_srd {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set die [$blk getDieArea]; set H [expr {[$die yMax] / double($u)}]
    set dens [qb_env QB10_SDENS 0.5]
    set halo [lindex [p MACRO_HALO] 1]
    # ---- s_q ports -> x (um)
    array set px {}
    set ports {}
    foreach bt [$blk getBTerms] {
        set n [$bt getName]
        if {![regexp {^u_top_s_q(\[\d+\]|_\d+_)$} $n]} continue
        set bb [$bt getBBox]
        set px($n) [expr {([$bb xMin] + [$bb xMax]) / 2.0 / $u}]
        lappend ports $bt
    }
    # ---- backward cone (comb std cells), level = longest distance to a port, reached-port x sum / count
    array set lvl {}; array set src {}; array set reach {}; array set ctl {}
    set stack {}
    foreach bt $ports {
        set net [$bt getNet]; if {$net eq "NULL"} continue
        foreach it [$net getITerms] {
            if {![$it isOutputSignal]} continue
            lappend stack [list [$it getInst] 0 [$bt getName]]
        }
    }
    proc ::qb10_isseq {m} { return [regexp {^(DF|EDF|SDF|LH|LN|CKLN|SDN|DFN)} [$m getName]] }
    while {[llength $stack]} {
        set e [lindex $stack end]; set stack [lreplace $stack end end]
        lassign $e i l p
        set m [$i getMaster]
        if {[$m isBlock] || [::qb10_isseq $m]} continue
        set k [$i getName]
        set new 0
        if {![info exists lvl($k)]} { set lvl($k) $l; set new 1; set reach($k) [dict create $p 1]
        } else {
            if {$l > $lvl($k)} { set lvl($k) $l; set new 1 }
            if {![dict exists $reach($k) $p]} { dict set reach($k) $p 1; set new 1 }
        }
        if {!$new} continue
        foreach it [$i getITerms] {
            if {![$it isInputSignal]} continue
            set net [$it getNet]; if {$net eq "NULL"} continue
            set st [$net getSigType]; if {$st eq "POWER" || $st eq "GROUND" || $st eq "CLOCK"} continue
            foreach d [$net getITerms] {
                if {![$d isOutputSignal]} continue
                set di [$d getInst]; set dm [$di getMaster]
                if {[$dm isBlock]} {
                    if {[regexp {g_s_(\d+)_} [$di getName] - ln]} { dict set src($k) $ln $di } else { set ctl($k) 1 }
                } elseif {[::qb10_isseq $dm]} { set ctl($k) 1
                } else { lappend stack [list $di [expr {$l + 1}] $p] }
            }
        }
    }
    # sources propagate from the leaves towards the ports: iterate by decreasing level
    array unset ::qb10_lvl; array set ::qb10_lvl [array get lvl]
    set cells [lsort -command {apply {{a b} { expr {$::qb10_lvl($b) - $::qb10_lvl($a)} }}} [array names lvl]]
    # fan-in sources: union over comb drivers (DAG; process deepest first)
    foreach k $cells {
        set i [$blk findInst $k]
        foreach it [$i getITerms] {
            if {![$it isInputSignal]} continue
            set net [$it getNet]; if {$net eq "NULL"} continue
            foreach d [$net getITerms] {
                if {![$d isOutputSignal]} continue
                set dk [[$d getInst] getName]
                if {[info exists lvl($dk)] && [info exists src($dk)]} {
                    if {![info exists src($k)]} { set src($k) [dict create] }
                    set src($k) [dict merge $src($k) $src($dk)]
                }
            }
        }
    }
    # ---- S macro rows / channels (macro bboxes, um)
    array set mrow {}
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isBlock] || ![regexp {g_s_(\d+)_} [$i getName] - ln]} continue
        set b [$i getBBox]
        set r [expr {$ln / 8}]
        lappend mrow($r) [list [expr {[$b yMin] / double($u)}] [expr {[$b yMax] / double($u)}]]
    }
    set ch {}
    for {set r 0} {$r < 3} {incr r} {
        set top [tcl::mathfunc::max {*}[lmap v $mrow($r) {lindex $v 1}]]
        set bot [tcl::mathfunc::min {*}[lmap v $mrow([expr {$r + 1}]) {lindex $v 0}]]
        lappend ch [list [expr {$top + $halo + 0.5}] [expr {$bot - $halo - 0.5}]]
    }
    # ---- classify
    set nloc 0; set nbody 0; set nctl 0; set nother 0
    array set G {}; array set G_loc {}
    set lmax 0
    foreach k $cells {
        if {![info exists src($k)] || [dict size $src($k)] == 0} { incr nctl; continue }
        set cols [lsort -unique [lmap ln [dict keys $src($k)] {expr {$ln % 8}}]]
        set i [$blk findInst $k]
        set w [expr {[[$i getMaster] getWidth] / double($u)}]
        if {[llength $cols] == 1} {
            set sx 0.0; set sy 0.0; set n 0
            dict for {ln mi} $src($k) {
                set b [$mi getBBox]
                set sx [expr {$sx + ([$b xMin] + [$b xMax]) / 2.0 / $u}]; set sy [expr {$sy + [$b yMax] / double($u)}]; incr n
            }
            set tx [expr {$sx / $n}]; set ty [expr {$sy / $n}]
            set bi 0; set bd 1e9
            for {set c 0} {$c < 3} {incr c} {
                lassign [lindex $ch $c] a b; set d [expr {abs(($a + $b) / 2.0 - $ty)}]
                if {$d < $bd} { set bd $d; set bi $c }
            }
            lappend G(ch$bi,[lindex $cols 0]) [list $i $tx $w]
            set G_loc($k) $bi
            incr nloc
        } else {
            set sx 0.0; set n 0
            foreach p [dict keys $reach($k)] { set sx [expr {$sx + $px($p)}]; incr n }
            lappend G(lv$lvl($k)) [list $i [expr {$sx / $n}] $w]
            set lmax [expr {max($lmax, $lvl($k))}]
            incr nbody
        }
    }
    # ---- shelf packing: band rows {y0 y1}, x range {xa xb}; cell -> row minimising |x - target|
    set site 0.2; set rowh 1.8; set cy0 5.0
    proc ::qb10_pack {items y0 y1 xa xb dens site rowh cy0 u} {
        set r0 [expr {int(ceil(($y0 - $cy0) / $rowh))}]; set r1 [expr {int(floor(($y1 - $cy0) / $rowh)) - 1}]
        if {$r1 < $r0} { error "srd: empty band $y0 $y1" }
        set cur {}; for {set r $r0} {$r <= $r1} {incr r} { lappend cur $xa }
        set items [lsort -real -index 1 $items]
        set nfail 0; set disp 0.0
        foreach it $items {
            lassign $it i t w
            set best -1; set bx 0; set bd 1e18
            for {set r 0} {$r < [llength $cur]} {incr r} {
                set x [expr {max([lindex $cur $r], $t - $w / 2.0)}]
                set x [expr {round($x / $site) * $site}]
                if {$x < [lindex $cur $r]} { set x [expr {$x + $site}] }
                if {$x + $w > $xb} continue
                set d [expr {abs($x + $w / 2.0 - $t)}]
                if {$d < $bd} { set bd $d; set best $r; set bx $x }
            }
            if {$best < 0} { incr nfail; continue }
            lset cur $best [expr {$bx + $w / $dens}]
            set y [expr {$cy0 + ($r0 + $best) * $rowh}]
            $i setOrient [expr {(($r0 + $best) % 2) ? "MX" : "R0"}]
            $i setLocation [expr {round($bx * $u)}] [expr {round($y * $u)}]
            $i setPlacementStatus FIRM
            lappend ::qb10_firm $i
            set disp [expr {$disp + $bd}]
        }
        return [list [llength $items] $nfail [expr {[llength $items] ? $disp / [llength $items] : 0}]]
    }
    set ::qb10_firm {}
    # QB10_NWLVL n: only body levels <= n go to the north-west region; deeper multi-column cells (a cross-column select
    # tree, e.g. QB_WB_COL's 8:1 lane select) are placed level by level (deepest first) at the mean position of their
    # drivers, in the nearest macro-row channel (lower half), so the tree reduces inside the S rows before going west
    set nwl [qb_env QB10_NWLVL 99]
    set f [open $::OUT/rpt/srd.txt w]
    puts $f "SRD cone: column-local $nloc, multi-column (body) $nbody, no S source (control) $nctl, levels 0..$lmax, s_q ports [llength $ports], density $dens"
    puts $f "SRD channels (y um): [join [lmap c $ch {format {%.1f-%.1f} {*}$c}] {, }]"
    foreach g [lsort [array names G ch*]] {
        regexp {ch(\d),(\d)} $g - c col
        lassign [lindex $ch $c] y0 y1
        if {$nwl < $lmax} { set y0 [expr {($y0 + $y1) / 2.0}] }
        set xs [lmap v $G($g) {lindex $v 1}]
        set xa [expr {max(5.0, [tcl::mathfunc::min {*}$xs] - 200.0)}]; set xb [expr {min(3985.0, [tcl::mathfunc::max {*}$xs] + 200.0)}]
        set r [::qb10_pack $G($g) $y0 $y1 $xa $xb $dens $site $rowh $cy0 $u]
        puts $f [format "SRD local col %d channel %d (y %.1f-%.1f): cells %d failed %d mean |dx| %.1f um" $col $c $y0 $y1 {*}$r]
    }
    array set srcch {}
    for {set l $lmax} {$l > $nwl} {incr l -1} {
        if {![info exists G(lv$l)]} continue
        array unset SG; array set SG {}
        foreach v $G(lv$l) {
            lassign $v i t w
            set sx 0.0; set sy 0.0; set n 0
            foreach it [$i getITerms] {
                if {![$it isInputSignal]} continue
                set net [$it getNet]; if {$net eq "NULL"} continue
                foreach d [$net getITerms] {
                    if {![$d isOutputSignal]} continue
                    set di [$d getInst]; set dn [$di getName]
                    if {[[$di getMaster] isBlock] && [regexp {g_s_\d+_} $dn]} {
                        set b [$di getBBox]; set x [expr {([$b xMin] + [$b xMax]) / 2.0 / $u}]; set y [expr {[$b yMax] / double($u)}]
                    } elseif {[info exists srcch($dn)] || [info exists G_loc($dn)]} {
                        lassign [$di getLocation] x y; set x [expr {$x / double($u)}]; set y [expr {$y / double($u)}]
                    } else continue
                    set sx [expr {$sx + $x}]; set sy [expr {$sy + $y}]; incr n
                }
            }
            if {$n == 0} { lappend G(lv$nwl) $v; continue }
            set tx [expr {$sx / $n}]; set ty [expr {$sy / $n}]
            set bi 0; set bd 1e9
            for {set c 0} {$c < 3} {incr c} { lassign [lindex $ch $c] a b; set d [expr {abs(($a + $b) / 2.0 - $ty)}]; if {$d < $bd} { set bd $d; set bi $c } }
            lappend SG($bi) [list $i $tx $w]
            set srcch([$i getName]) $bi
        }
        foreach c [lsort [array names SG]] {
            lassign [lindex $ch $c] y0 y1
            set r [::qb10_pack $SG($c) $y0 [expr {($y0 + $y1) / 2.0}] 860.0 3985.0 $dens $site $rowh $cy0 $u]
            puts $f [format "SRD tree level %d channel %d: cells %d failed %d mean |dx| %.1f um" $l $c {*}$r]
        }
        unset G(lv$l)
    }
    set rx0 [qb_env QB10_RX0 15]; set rx1 [qb_env QB10_RX1 850]; set ytop [expr {$H - 8.0}]
    for {set l 0} {$l <= $lmax} {incr l} {
        if {![info exists G(lv$l)]} continue
        set a 0.0; foreach v $G(lv$l) { set a [expr {$a + [lindex $v 2] * $rowh}] }
        set nr [expr {int(ceil($a / $dens / ($rx1 - $rx0) / $rowh * 1.5)) + 1}]
        set y1 $ytop; set y0 [expr {$ytop - $nr * $rowh - 0.01}]
        if {$y0 < [qb_env QB10_RY0 1526]} { error "srd: body region full at level $l (y0 $y0)" }
        set r [::qb10_pack $G(lv$l) $y0 $y1 $rx0 $rx1 $dens $site $rowh $cy0 $u]
        puts $f [format "SRD body level %d (y %.1f-%.1f, %d rows): cells %d failed %d mean |dx| %.1f um" $l $y0 $y1 $nr {*}$r]
        set ytop [expr {$y0 - 0.01}]
    }
    # ---- westward buffers (QB10_WBUF 1): every net from an S macro Q pin or a column-local cell into the body gets a
    # buffer at the west end of the S macro rows (x QB10_WBX0..QB10_WBX1, at the channel of its source), the body sinks
    # moved to the buffer output: the long part (column -> west strip) is then a straight horizontal 2-pin net inside
    # the S macro row region (M5 / M7 / M9 free over the macros), not an L through the band
    if {[qb_env QB10_WBUF 1]} {
        array set isbody {}; foreach v [array names G lv*] { foreach it $G($v) { set isbody([[lindex $it 0] getName]) 1 } }
        array set locch {}; foreach g [array names G ch*] { regexp {ch(\d),} $g - c; foreach it $G($g) { set locch([[lindex $it 0] getName]) $c } }
        array set locch [array get srcch]
        set bm [[ord::get_db] findMaster [qb_env QB10_WBM BUFFD2]]
        set nets {}
        foreach k [array names isbody] {
            foreach it [[$blk findInst $k] getITerms] {
                if {![$it isInputSignal]} continue
                set net [$it getNet]; if {$net eq "NULL"} continue
                lappend nets $net
            }
        }
        set wx0 [qb_env QB10_WBX0 662]; set wx1 [qb_env QB10_WBX1 846]; set hb [qb_env QB10_WBH 110]
        set nbuf 0; array set WB {}; array set WBP {}
        foreach net [lsort -unique $nets] {
            set drv ""; set bs {}
            foreach it [$net getITerms] {
                if {[$it isOutputSignal]} { set drv $it } elseif {[info exists isbody([[$it getInst] getName])]} { lappend bs $it }
            }
            if {$drv eq "" || ![llength $bs]} continue
            set di [$drv getInst]; set dn [$di getName]
            if {[[$di getMaster] isBlock]} {
                if {![regexp {g_s_(\d+)_} $dn - ln]} continue
                set c [expr {min(2, $ln / 8)}]
            } elseif {[info exists locch($dn)]} { set c $locch($dn) } else continue
            set nn [odb::dbNet_create $blk "srdw_n$nbuf"]
            set b [odb::dbInst_create $blk $bm "srdw_b$nbuf"]
            [$b findITerm I] connect $net
            [$b findITerm Z] connect $nn
            foreach it $bs { $it disconnect; $it connect $nn }
            set dx [lindex [$di getLocation] 0]
            lappend WB($c) [list $b $dx [expr {[$bm getWidth] / double($u)}]]
            incr nbuf
        }
        foreach c [lsort [array names WB]] {
            # targets: spread evenly over the strip in the order of the source x (eastern sources at the east end)
            set l [lsort -integer -index 1 $WB($c)]; set n [llength $l]; set WB($c) {}
            for {set k 0} {$k < $n} {incr k} { lset l $k 1 [expr {$wx0 + ($wx1 - $wx0 - 12.0) * ($k + 0.5) / $n}] }
            set WB($c) $l
            lassign [lindex $ch $c] a b; set ym [expr {($a + $b) / 2.0}]
            set r [::qb10_pack $WB($c) [expr {$ym - $hb}] [expr {$ym + $hb}] $wx0 $wx1 $dens $site $rowh $cy0 $u]
            puts $f [format "SRD west buffers channel %d (y %.1f +- %g, x %g-%g): buffers %d failed %d" $c $ym $hb $wx0 $wx1 {*}[lrange $r 0 1]]
        }
        # QB10_NWLVL < 0: no north-west body; the s_q port nets from channel-placed cells get the west buffer instead
        if {$nwl < 0} {
            foreach bt $ports {
                set net [$bt getNet]; if {$net eq "NULL"} continue
                set drv ""; foreach it [$net getITerms] { if {[$it isOutputSignal]} { set drv $it } }
                if {$drv eq ""} continue
                set dn [[$drv getInst] getName]; if {![info exists locch($dn)]} continue
                set c $locch($dn)
                set nn [odb::dbNet_create $blk "srdw_n$nbuf"]
                set b [odb::dbInst_create $blk $bm "srdw_b$nbuf"]
                $bt connect $nn
                [$b findITerm Z] connect $nn
                [$b findITerm I] connect $net
                lappend WBP($c) [list $b [lindex [[$drv getInst] getLocation] 0] [expr {[$bm getWidth] / double($u)}]]
                incr nbuf
            }
            foreach c [lsort [array names WBP]] {
                set l [lsort -integer -index 1 $WBP($c)]; set n [llength $l]
                for {set k 0} {$k < $n} {incr k} { lset l $k 1 [expr {$wx0 + ($wx1 - $wx0 - 12.0) * ($k + 0.5) / $n}] }
                lassign [lindex $ch $c] a b; set ym [expr {($a + $b) / 2.0}]
                set r [::qb10_pack $l [expr {$ym - $hb}] [expr {$ym + $hb}] $wx0 $wx1 $dens $site $rowh $cy0 $u]
                puts $f [format "SRD west port buffers channel %d: buffers %d failed %d" $c {*}[lrange $r 0 1]]
            }
        }
        puts $f "SRD westward nets buffered: $nbuf"
    }
    close $f
    qc_log "r10b srd: column-local $nloc, body $nbody, control $nctl, levels $lmax, FIRM [llength $::qb10_firm] (rpt/srd.txt)"
}
qb10_srd
# release the FIRM cells right before the first detailed placement (they are on legal sites; repair may have resized)
if {[info commands qb10_dpl_orig] eq ""} {
    rename detailed_placement qb10_dpl_orig
    proc detailed_placement {args} {
        if {[info exists ::qb10_firm]} {
            foreach i $::qb10_firm { $i setPlacementStatus PLACED }
            qc_log "r10b srd: [llength $::qb10_firm] cells released (PLACED) before detailed placement"
            unset ::qb10_firm
        }
        qb10_dpl_orig {*}$args
    }
}
# QB10_REL repair (default): release the FIRM cells already before the place step's first DRV repair, i.e. after the
# initial global placement only (r10b_oB / cB with FIRM through the incremental passes: GPL-0305 divergence at 0.86)
if {[qb_env QB10_REL repair] eq "repair" && [info commands qb10_drv_prev] eq ""} {
    rename qc_repair_drv qb10_drv_prev
    proc qc_repair_drv {} {
        if {[info exists ::qb10_firm]} {
            foreach i $::qb10_firm { $i setPlacementStatus PLACED }
            qc_log "r10b srd: [llength $::qb10_firm] cells released (PLACED) before the DRV repair"
            unset ::qb10_firm
        }
        qb10_drv_prev
    }
}
