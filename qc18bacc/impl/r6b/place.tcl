# PRE_PLACE_TCL of impl/r6b/chip.cfg (results/r6b.md): group template placement.
#   1. max transition QB_MAXTRAN (0.4 ns, as impl/r5b/pre_place.tcl run v); the DC buffers were removed by prep.tcl
#   2. global_placement: the cells of every group file <run>/grp_<g>.pos (impl/r6b/grp_place.tcl: each group placed
#      standalone in its rectangles) are imported FIRM; the flow's gpl places only the rest (tie cells, no-group
#      cells); then PLACED
#   3. qc_repair_drv: DRV repair; QB_INC (default 0) 1: incremental gpl with the imported cells FIRM (QB_INC_DENS, only
#      repair buffers move: the R5c QB_INC_POST step), 2: incremental gpl of every cell (impl/pnr/gpl_incr.tcl as R5b),
#      each followed by a second DRV repair
#   4. detailed placement (flow): legalises everything; QB_DPL_ARGS
if {[qb_env QB_MAXTRAN 0.4] ne ""} { set_max_transition [qb_env QB_MAXTRAN 0.4] [current_design]; qc_log "r6b: max_transition [qb_env QB_MAXTRAN 0.4]" }
set ::QB6_INSTS {}
array set ::QB6_M {}
proc qb6_import {} {
    set blk [ord::get_db_block]
    set n 0; set miss 0
    foreach g {S WA W N} {
        set pf $::OUT/grp_$g[qb_env QB_POS_TAG ""].pos
        if {![file exists $pf]} { qc_log "r6b: no $pf"; continue }
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
        qc_log "r6b: group $g $k cells imported FIRM"; incr n $k
    }
    set left 0
    foreach i [$blk getInsts] { if {![[$i getMaster] isBlock] && [$i getPlacementStatus] in {NONE UNPLACED}} { incr left } }
    qc_summary "r6b_import cells $n not_found $miss left_for_gpl $left"
    return $left
}
proc qb6_status {st} { foreach i $::QB6_INSTS { $i setPlacementStatus $st } }
rename global_placement qb6_gpl_orig
proc global_placement {args} {
    set left [qb6_import]
    set t [clock seconds]
    if {$left > 0} { qb6_gpl_orig {*}$args }
    qc_log "r6b: gpl of the $left remaining cells [expr {[clock seconds] - $t}] s"
    qb6_status PLACED
}
if {[info commands qb6_drv_orig] eq ""} {
    rename qc_repair_drv qb6_drv_orig
    proc qc_repair_drv {} {
        set n0 [llength [[ord::get_db_block] getInsts]]
        qb6_drv_orig
        qc_log "r6b: DRV repair 1 added [expr {[llength [[ord::get_db_block] getInsts]] - $n0}] instances [qc_util]"
        if {[qb_env QB_INC 0]} {
            # QB_INC 1: groups FIRM (failed in r6b_a: GPL-0302, suggested density -1.59 with 560 k FIRM cells + macros);
            # QB_INC 2: every cell movable (incremental gpl from the group placement)
            if {[qb_env QB_INC 0] == 1} { qb6_status FIRM }
            set t [clock seconds]
            qb6_gpl_orig -incremental -density [qb_env QB_INC_DENS 0.80] -pad_left 0 -pad_right 0
            qb6_status PLACED
            qc_log "r6b: incremental gpl (groups FIRM) [expr {[clock seconds] - $t}] s"
            estimate_parasitics -placement
            set n1 [llength [[ord::get_db_block] getInsts]]
            qb6_drv_orig
            qc_log "r6b: DRV repair 2 added [expr {[llength [[ord::get_db_block] getInsts]] - $n1}] instances [qc_util]"
        }
    }
}
# QB_SNAP 1: before the first detailed placement, every standard cell whose origin lies inside a block / macro
# footprint (+ halo QB_SNAP_HALO um; the 8 abutted columns as one rectangle) is moved to the nearest point just
# outside it, so detailed placement only makes short moves (r6b_a: DRV-repair buffers on nets across the array /
# macro rows, single-threaded detailed placement > 12 min).
proc qb6_snap {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set h [expr {round([qb_env QB_SNAP_HALO 8.0] * $u)}]
    set rs {}; set ax1 1e18; set ay1 1e18; set ax2 -1e18; set ay2 -1e18
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isBlock]} continue
        set b [$i getBBox]
        if {[[$i getMaster] getName] eq "qb_col_blk"} {
            set ax1 [expr {min($ax1, [$b xMin])}]; set ay1 [expr {min($ay1, [$b yMin])}]
            set ax2 [expr {max($ax2, [$b xMax])}]; set ay2 [expr {max($ay2, [$b yMax])}]
        } else { lappend rs [list [expr {[$b xMin] - $h}] [expr {[$b yMin] - $h}] [expr {[$b xMax] + $h}] [expr {[$b yMax] + $h}]] }
    }
    lappend rs [list [expr {$ax1 - $h}] [expr {$ay1 - $h}] [expr {$ax2 + $h}] [expr {$ay2 + $h}]]
    set g [expr {100 * $u}]
    array set bk {}
    set k 0
    foreach r $rs {
        lassign $r a b c d
        for {set x [expr {$a / $g}]} {$x <= $c / $g} {incr x} { for {set y [expr {$b / $g}]} {$y <= $d / $g} {incr y} { lappend bk($x,$y) $k } }
        incr k
    }
    set core [$blk getCoreArea]
    set n 0; array set fan {}
    foreach i [$blk getInsts] {
        if {[[$i getMaster] isBlock] || [$i getPlacementStatus] ne "PLACED"} continue
        lassign [$i getLocation] x y
        set key "[expr {$x / $g}],[expr {$y / $g}]"
        if {![info exists bk($key)]} continue
        foreach k $bk($key) {
            lassign [lindex $rs $k] a b c d
            if {$x < $a || $x >= $c || $y < $b || $y >= $d} continue
            set w [[$i getMaster] getWidth]; set hh [[$i getMaster] getHeight]
            set best {}
            foreach {dx nx ny} [list [expr {$x - $a + $w}] [expr {$a - $w}] $y  [expr {$c - $x}] $c $y \
                                     [expr {$y - $b + $hh}] $x [expr {$b - $hh}]  [expr {$d - $y}] $x $d] {
                if {$nx < [$core xMin] || $nx + $w > [$core xMax] || $ny < [$core yMin] || $ny + $hh > [$core yMax]} continue
                if {$best eq "" || $dx < [lindex $best 0]} { set best [list $dx $nx $ny] }
            }
            if {$best ne ""} {
                lassign $best dd nx ny
                if {[qb_env QB_SNAP 1] == 2} {
                    # fan-out: cells snapped to the same 4-um edge slot are stacked away from the macro, so they do
                    # not pile up at one point (one diamond search per cell over the pile)
                    if {$nx == $a - $w || $nx == $c} { set key2 "$k,[expr {$nx == $c}],[expr {$ny / (4 * $u)}]" } else { set key2 "$k,y[expr {$ny == $d}],[expr {$nx / (4 * $u)}]" }
                    if {![info exists fan($key2)]} { set fan($key2) 0 }
                    set off [expr {$fan($key2)}]; incr fan($key2) [expr {$nx == $a - $w || $nx == $c ? $w : $hh}]
                    if {$nx == $a - $w} { set nx [expr {$nx - $off}] } elseif {$nx == $c} { set nx [expr {$nx + $off}] } elseif {$ny == $d} { set ny [expr {$ny + $off}] } else { set ny [expr {$ny - $off}] }
                    set nx [expr {max([$core xMin], min([$core xMax] - $w, $nx))}]; set ny [expr {max([$core yMin], min([$core yMax] - $hh, $ny))}]
                }
                $i setLocation $nx $ny; incr n
            }
            break
        }
    }
    qc_log "r6b: snap $n cells out of block / macro footprints"
}
if {[qb_env QB_SNAP 0]} {
    rename detailed_placement qb6_dpl_orig
    proc detailed_placement {args} {
        if {[info exists ::QB6_SNAPPED]} { qb6_dpl_orig {*}$args; return }
        set ::QB6_SNAPPED 1
        set t [clock seconds]
        qb6_snap
        # QB_DPL_FIRM 1: the legalised group cells (grp_<g>_L.pos with orientation) whose master the DRV repair kept
        # are FIRM in this detailed placement; only repair buffers, resized cells and unlegalised groups move
        if {[qb_env QB_DPL_FIRM 0]} {
            set nf 0
            foreach i $::QB6_INSTS { if {[info exists ::QB6_M($i)] && $::QB6_M($i) eq [[$i getMaster] getName]} { $i setPlacementStatus FIRM; incr nf } }
            qc_log "r6b: $nf legal group cells FIRM for the first detailed placement"
        }
        qb6_dpl_orig {*}$args
        qb6_status PLACED
        qc_log "r6b: first detailed placement (after snap) [expr {[clock seconds] - $t}] s"
    }
}
# QB_STOP_DPL 1: write db/predpl.odb (+ .sdc) just before the first detailed placement and exit (dpl probes)
if {[qb_env QB_STOP_DPL 0]} {
    rename detailed_placement qb6_dpl_stop
    proc detailed_placement {args} { write_db $::OUT/db/predpl.odb; write_sdc $::OUT/db/predpl.sdc; qc_log "r6b: predpl written"; exit }
}
# QB_SPREAD 1: coarse bin spreading before the first detailed placement.  Bins of QB_SPREAD_BX um (10) x one row;
# capacity = row length in the bin x QB_SPREAD_FILL (0.95); occupancy = the cells that stay (legal group cells with
# their master unchanged, macros cut the rows); every other standard cell (repair buffers, resized cells, unlegalised
# groups) goes to the nearest bin with room (offsets sorted by distance, up to QB_SPREAD_R um), packed left to right.
# Mechanism (r6b probes): detailed placement spent > 40 min in diamond search on the DRV-repair buffers, which
# repair_design drops in piles (fan-out trees at one point), while a group's 250 k gpl cells legalise in 2-7 s.
proc qb6_spread {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set bx [expr {round([qb_env QB_SPREAD_BX 10.0] * $u)}]
    set fill [qb_env QB_SPREAD_FILL 0.95]
    set r0 [lindex [$blk getRows] 0]
    set rh [[$r0 getSite] getHeight]
    set core [$blk getCoreArea]; set cx0 [$core xMin]; set cy0 [$core yMin]
    array set cap {}; array set occ {}; array set rowo {}
    foreach rw [$blk getRows] {
        set b [$rw getBBox]
        set j [expr {([$b yMin] - $cy0) / $rh}]
        set rowo($j) [list [$b yMin] [$rw getOrient]]
        for {set x [$b xMin]} {$x < [$b xMax]} {} {
            set i [expr {($x - $cx0) / $bx}]
            set xe [expr {min([$b xMax], $cx0 + ($i + 1) * $bx)}]
            set k "$i,$j"
            if {[info exists cap($k)]} { set cap($k) [expr {$cap($k) + ($xe - $x) * $fill}] } else { set cap($k) [expr {($xe - $x) * $fill}]; set occ($k) 0 }
            set x $xe
        }
    }
    set mov {}
    foreach i [$blk getInsts] {
        set m [$i getMaster]
        if {[$m isBlock]} continue
        if {[info exists ::QB6_M($i)] && $::QB6_M($i) eq [$m getName]} {
            lassign [$i getLocation] x y
            set k "[expr {($x - $cx0) / $bx}],[expr {($y - $cy0) / $rh}]"
            if {[info exists occ($k)]} { set occ($k) [expr {$occ($k) + [$m getWidth]}] }
        } elseif {[$i getPlacementStatus] eq "PLACED"} { lappend mov $i }
    }
    set rr [expr {[qb_env QB_SPREAD_R 150.0] * $u}]
    set offs {}
    set nx [expr {int($rr / $bx)}]; set ny [expr {int($rr / $rh)}]
    for {set dx -$nx} {$dx <= $nx} {incr dx} { for {set dy -$ny} {$dy <= $ny} {incr dy} {
        set d [expr {hypot($dx * $bx, $dy * $rh)}]; if {$d <= $rr} { lappend offs [list $d $dx $dy] } } }
    set offs [lsort -real -index 0 $offs]
    set n 0; set far 0; set fail 0
    foreach i $mov {
        set w [[$i getMaster] getWidth]
        lassign [$i getLocation] x y
        set bi [expr {($x - $cx0) / $bx}]; set bj [expr {($y - $cy0) / $rh}]
        set done 0
        foreach o $offs {
            set k "[expr {$bi + [lindex $o 1]}],[expr {$bj + [lindex $o 2]}]"
            if {![info exists cap($k)] || $occ($k) + $w > $cap($k)} continue
            lassign [split $k ,] ki kj
            set nxp [expr {$cx0 + $ki * $bx + $occ($k)}]
            set nxp [expr {$nxp - ($nxp - $cx0) % 400 + 0}]
            $i setLocation $nxp [lindex $rowo($kj) 0]
            $i setOrient [lindex $rowo($kj) 1]
            set occ($k) [expr {$occ($k) + $w}]
            incr n; if {[lindex $o 0] > 20 * $u} { incr far }
            set done 1; break
        }
        if {!$done} { incr fail }
    }
    qc_log "r6b: spread [llength $mov] movable cells: $n binned ($far > 20 um), $fail without a bin within [qb_env QB_SPREAD_R 150.0] um"
}
if {[qb_env QB_SPREAD 0]} {
    if {[info commands qb6_snap_orig] eq ""} {
        rename qb6_snap qb6_snap_orig
        proc qb6_snap {} { qb6_snap_orig; qb6_spread }
    }
}
# QB_SPREAD 2: the same on QB_SPREAD_SB-um (100) super-bins, nearest super-bin with room over the whole die, random
# position inside it (QB_SPREAD 1 scanned fine-bin offsets per cell: > 15 min in Tcl on r6b_c's piles)
proc qb6_spread2 {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set sb [expr {round([qb_env QB_SPREAD_SB 100.0] * $u)}]
    set fill [qb_env QB_SPREAD_FILL 0.90]
    set core [$blk getCoreArea]; set cx0 [$core xMin]; set cy0 [$core yMin]
    array set sp {}; array set rows {}
    foreach rw [$blk getRows] {
        set b [$rw getBBox]
        set j [expr {([$b yMin] - $cy0) / $sb}]
        for {set x [$b xMin]} {$x < [$b xMax]} {} {
            set i [expr {($x - $cx0) / $sb}]
            set xe [expr {min([$b xMax], $cx0 + ($i + 1) * $sb)}]
            set k "$i,$j"
            if {![info exists sp($k)]} { set sp($k) 0.0 }
            set sp($k) [expr {$sp($k) + ($xe - $x) * double([$b dy]) * $fill}]
            lappend rows($k) [list $x $xe [$b yMin] [$rw getOrient]]
            set x $xe
        }
    }
    set mov {}
    foreach i [$blk getInsts] {
        set m [$i getMaster]
        if {[$m isBlock]} continue
        if {[info exists ::QB6_M($i)] && $::QB6_M($i) eq [$m getName]} {
            lassign [$i getLocation] x y
            set k "[expr {($x - $cx0) / $sb}],[expr {($y - $cy0) / $sb}]"
            if {[info exists sp($k)]} { set sp($k) [expr {$sp($k) - double([$m getWidth]) * [$m getHeight]}] }
        } elseif {[$i getPlacementStatus] eq "PLACED"} { lappend mov $i }
    }
    set nx [expr {[$core dx] / $sb + 1}]; set ny [expr {[$core dy] / $sb + 1}]
    set offs {}
    for {set dx -$nx} {$dx <= $nx} {incr dx} { for {set dy -$ny} {$dy <= $ny} {incr dy} { lappend offs [list [expr {hypot($dx, $dy)}] $dx $dy] } }
    set offs [lsort -real -index 0 $offs]
    expr {srand(7)}
    set n 0; set far 0; set fail 0; set dsum 0.0
    foreach i $mov {
        set m [$i getMaster]; set a [expr {double([$m getWidth]) * [$m getHeight]}]
        lassign [$i getLocation] x y
        set bi [expr {($x - $cx0) / $sb}]; set bj [expr {($y - $cy0) / $sb}]
        set k "$bi,$bj"
        if {[info exists sp($k)] && $sp($k) >= $a} { set sp($k) [expr {$sp($k) - $a}]; incr n; continue }
        set done 0
        foreach o $offs {
            set k "[expr {$bi + [lindex $o 1]}],[expr {$bj + [lindex $o 2]}]"
            if {![info exists sp($k)] || $sp($k) < $a} continue
            set sp($k) [expr {$sp($k) - $a}]
            set r [lindex $rows($k) [expr {int(rand() * [llength $rows($k)])}]]
            lassign $r x1 x2 yy ro
            set xn [expr {$x1 + int(rand() * max(1, $x2 - $x1 - [$m getWidth]))}]
            set xn [expr {$xn - ($xn - $cx0) % 400}]
            $i setLocation $xn $yy; $i setOrient $ro
            incr n; incr far; set dsum [expr {$dsum + [lindex $o 0]}]
            set done 1; break
        }
        if {!$done} { incr fail }
    }
    qc_log [format "r6b: spread2 %d movable cells: %d kept in their super-bin, %d moved (mean %.1f super-bins), %d failed" \
        [llength $mov] [expr {$n - $far}] $far [expr {$dsum / max(1, $far)}] $fail]
}
if {[qb_env QB_SPREAD 0] == 2} { proc qb6_spread {} { qb6_spread2 } }
# QB_SPREAD_ALL 1 (with QB_SPREAD 2): every later detailed placement (CTS, post-CTS repair) is preceded by spread2 of
# the cells added or resized since the previous one (the master record is refreshed after each detailed placement).
proc qb6_record {} { array unset ::QB6_M; foreach i [[ord::get_db_block] getInsts] { if {![[$i getMaster] isBlock]} { set ::QB6_M($i) [[$i getMaster] getName] } } }
if {[qb_env QB_SPREAD_ALL 0] && [qb_env QB_SPREAD 0] == 2} {
    rename detailed_placement qb6_dpl_all
    proc detailed_placement {args} {
        if {![info exists ::QB6_FIRST_DONE]} {
            set ::QB6_FIRST_DONE 1
            qb6_dpl_all {*}$args
        } else {
            set t [clock seconds]
            qb6_spread2
            qb6_dpl_all {*}$args
            qc_log "r6b: detailed placement after spread2 [expr {[clock seconds] - $t}] s"
        }
        qb6_record
    }
}
