# PRE_PLACE_TCL of impl/hard/col.cfg (results/pnr_pe.md).  Global placement and the DRV repair (buffers on long nets
# over the blocks) leave standard cells on top of the PE blocks / their halos, where the rows are cut; the first
# detailed placement then has to move them up to ~100 um and DPL-0036 / very slow legalisation followed (col_a).
# Wrap the first detailed_placement: before it, every movable cell whose centre lies inside a block box + halo is
# moved horizontally into the nearest legal area (the spine for both PE stacks; x clamped into the spine), keeping y;
# the count per region is logged.
rename global_placement qb_gpl_orig2
proc global_placement {args} {
    rename global_placement {}
    rename qb_gpl_orig2 global_placement
    global_placement {*}$args
    # QB_BR_PLACE 1 (after global placement, before the DRV repair, so that the repair buffers the final nets): global placement clusters decoders, CREG registers and both BR groups at levels 4-6 (col_a3:
    # GRT-0119 over the spine / blocks there); move BR group g to the spine at the centre of its 4 levels
    # (+- QB_BR_DY um) and the decoders / CREG port registers to the boundary between the groups (+- QB_DEC_DY um)
    if {[qb_env QB_BR_PLACE 1]} {
        set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
        set sx0 [expr {round(($::QB_XS + 0.5) * $u)}]; set sx1 [expr {round(($::QB_XS + $::QB_S - 0.5) * $u)}]
        array set nm {}
        foreach i [$blk getInsts] {
            set nmi [$i getName]; set yc ""
            if {[regexp {u_br} $nmi] && [regexp {g_grp_(\d+)__u_br/} $nmi -> g]} {
                set yc [expr {$::QB_YP + (4 * $g + 2) * $::QB_LP}]; set dy [qb_env QB_BR_DY 120.0]; set k br$g
            } elseif {[regexp {u_dec/|^u_core/(cdr|ctlr)_reg|^u_core/g_creg_(cdr|ctlr)} $nmi]} {
                set yc [expr {$::QB_YP + 4 * $::QB_LP}]; set dy [qb_env QB_DEC_DY 160.0]; set k dec
            }
            if {$yc eq ""} { continue }
            set m [$i getMaster]
            set nx [expr {$sx0 + int(rand() * ($sx1 - $sx0 - [$m getWidth]))}]
            set ny [expr {round(($yc + (rand() - 0.5) * 2 * $dy) * $u)}]
            $i setLocation $nx $ny
            incr nm($k)
        }
        qc_log "col_place: moved [lmap k [lsort [array names nm]] {string cat $k = $nm($k)}] into their spine windows"
    }
}
rename detailed_placement qb_dpl_orig
proc detailed_placement {args} {
    rename detailed_placement {}
    rename qb_dpl_orig detailed_placement
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set h [expr {round($::QB_HALO * $u)}]
    set boxes {}
    foreach i [$blk getInsts] {
        if {[[$i getMaster] isBlock]} { set b [$i getBBox]; lappend boxes [list [expr {[$b xMin] - $h}] [expr {[$b yMin] - $h}] [expr {[$b xMax] + $h}] [expr {[$b yMax] + $h}]] }
    }
    set sx0 [expr {round(($::QB_XS + 0.5) * $u)}]; set sx1 [expr {round(($::QB_XS + $::QB_S - 0.5) * $u)}]
    set yp [expr {round($::QB_YP * $u)}]
    set n 0; set nin 0
    foreach i [$blk getInsts] {
        set m [$i getMaster]
        if {[$m isBlock] || [$i isFixed]} { continue }
        lassign [$i getLocation] x y
        set cx [expr {$x + [$m getWidth] / 2}]; set cy [expr {$y + [$m getHeight] / 2}]
        if {$cy < $yp} { continue }
        incr n
        foreach bx $boxes {
            lassign $bx a b c d
            if {$cx > $a && $cx < $c && $cy > $b && $cy < $d} {
                set nx [expr {$sx0 + int(rand() * ($sx1 - $sx0 - [$m getWidth]))}]
                $i setLocation $nx $y
                incr nin
                break
            }
        }
    }
    qc_log "col_place: $nin of $n cells above the lane band were on a block / halo, moved into the spine"
    # diagnostics: cells whose nearest row has no segment under them; row-area utilisation of the lane band and of the spine
    array set rows {}
    foreach r [$blk getRows] { set b [$r getBBox]; lappend rows([$b yMin]) [list [$b xMin] [$b xMax]] }
    set ry0 [lindex [lsort -integer [array names rows]] 0]; set rh [[[lindex [$blk getRows] 0] getSite] getHeight]
    set nor 0; set aband 0.0; set aspine 0.0; set anor 0.0
    foreach i [$blk getInsts] {
        set m [$i getMaster]
        if {[$m isBlock]} { continue }
        lassign [$i getLocation] x y
        set a [expr {[$m getWidth] * double([$m getHeight]) / $u / $u}]
        if {$y < $yp} { set aband [expr {$aband + $a}] } else { set aspine [expr {$aspine + $a}] }
        set ok 0
        set ry [expr {$ry0 + round(($y - $ry0) / double($rh)) * $rh}]
        if {[info exists rows($ry)]} { foreach rb $rows($ry) { lassign $rb a0 c0; if {$x >= $a0 && $x + [$m getWidth] <= $c0} { set ok 1; break } } }
        if {!$ok} { incr nor; set anor [expr {$anor + $a}] }
    }
    set rband 0.0; set rspine 0.0
    foreach r [$blk getRows] { set b [$r getBBox]; set ra [expr {[$b dx] * double([$b dy]) / $u / $u}]; if {[$b yMin] < $yp} { set rband [expr {$rband + $ra}] } else { set rspine [expr {$rspine + $ra}] } }
    qc_log [format "col_place diag: lane band cells %.0f um2 / rows %.0f um2 (%.3f); above %.0f / %.0f (%.3f); %d cells (%.0f um2) outside every row" \
        $aband $rband [expr {$aband / $rband}] $aspine $rspine [expr {$aspine / max($rspine, 1.0)}] $nor $anor]
    if {[qb_env QB_PREDPL_DB 0]} { write_db $::OUT/db/pre_dpl.odb }
    set t [clock seconds]
    detailed_placement {*}$args
    qc_log "col_place: detailed placement [expr {[clock seconds] - $t}] s"
}
