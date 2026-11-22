# PRE_PLACE_TCL of blocks/col/col.cfg: placement of the column strip (results/pnr_slice3.md, r5c.md, r5a.md).
#   1. band seed: every cell in a small box at the centre of its band (floorplan/col_bands.tcl); the broadcast register
#      of group g between its rows (2 PE rows per broadcast register), decoders at the row 7 / 8 boundary
#   2. tile: the standalone placement of PE row r ($QB_TILE_DIR/r5c_t<r>/tile.txt, impl r5c pe_tile runs) is copied
#      into PE row r's slot: x from the core's west edge + QB_TILE_X, y from the first even row (same row orientation
#      as the template) at or above the bottom of row r's band; the PE cells are FIRM (gpl / DPL treat them as fixed)
#   3. timing-driven gpl from the seed (-skip_initial_place) places only the remaining cells (decoders, BRs,
#      feedthrough, lanes, banks); PE cells back to PLACED for the DRV repair
#   4. before the first legalisation: incremental global placement at density 0.8 with the PE cells FIRM again (only
#      repair buffers and non-PE cells move), then PLACED: legalisation, CTS, repair and their legalisations may move
#      PE cells
# Logs after gpl and after the first detailed placement (qb3_stats): per PE row placed centroid, 10-90 % y span,
# fraction within its band +- 0.25 band, monotone order; after detailed placement also the worst slack per class;
# PE-row spread (qb5c_spread) after tiling and after the first legalisation.
source $::QBF/floorplan/col_bands.tcl
qb_bands
# PE rows per broadcast register of the netlist (qb_core BRG; qb_col_cwfp_b2: 2); BR g is seeded between its rows
set ::QB_BRG 2
proc qb3_seed {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    expr {srand(908)}
    set xc [expr {($::QB_X0 + $::QB_X1) / 2.0}]
    set wx [expr {0.15 * ($::QB_X1 - $::QB_X0)}]
    set f 0.15
    array set cnt {}
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isCore] || [$i isFixed]} { continue }
        set c [qb_class [$i getName]]
        switch -glob -- $c {
            pe*   { lassign [qb_row_y [string range $c 2 end]] a b; set yc [expr {($a + $b) / 2.0}]; set wy [expr {$f * $::QB_HP}] }
            br*   { set g [string range $c 2 end]; lassign [qb_row_y [expr {$::QB_BRG * $g + $::QB_BRG / 2 - 1}]] a yc; set wy [expr {0.15 * $::QB_HP}] }
            dec   { lassign [qb_row_y 7] a yc; set wy [expr {0.15 * $::QB_HP}] }
            default { set yc [expr {$::QB_Y0 + $::QB_HL / 2.0}]; set wy [expr {$f * $::QB_HL}] }
        }
        set x [expr {$xc + (rand() - 0.5) * 2 * $wx}]
        set y [expr {$yc + (rand() - 0.5) * 2 * $wy}]
        $i setLocation [expr {int($x * $u)}] [expr {int($y * $u)}]
        $i setPlacementStatus PLACED
        incr cnt($c)
    }
    qc_log "slice3 seed (seed): [lmap k [lsort -dictionary [array names cnt]] {string cat $k = $cnt($k)}]"
}
# per-row placement statistics (the measurement of results/pnr_slice3.md)
proc qb3_stats {tag} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    array set ys {}; array set xs {}
    foreach i [$blk getInsts] {
        if {[regexp {^u_core/g_r_(\d+)__g_c_0__u_pe/} [$i getName] -> r]} {
            set m [$i getMaster]; lassign [$i getLocation] x y
            lappend ys($r) [expr {($y + [$m getHeight] / 2.0) / $u}]; lappend xs($r) [expr {($x + [$m getWidth] / 2.0) / $u}]
        }
    }
    set prev -1e9; set order 1; set inv 0; set out {}; set wspan 0.0; set minadh 1.0
    for {set r 0} {$r < 16} {incr r} {
        set l [lsort -real $ys($r)]; set k [llength $l]
        set s 0.0; foreach y $l { set s [expr {$s + $y}] }; set c [expr {$s / $k}]
        set p10 [lindex $l [expr {int(0.10 * $k)}]]; set p90 [lindex $l [expr {int(0.90 * $k)}]]
        set lx [lsort -real $xs($r)]; set q10 [lindex $lx [expr {int(0.10 * $k)}]]; set q90 [lindex $lx [expr {int(0.90 * $k)}]]
        lassign [qb_row_y $r] a b
        set in 0; foreach y $l { if {$y >= $a - 0.25 * $::QB_HP && $y <= $b + 0.25 * $::QB_HP} { incr in } }
        set adh [expr {$in / double($k)}]; set minadh [expr {min($minadh, $adh)}]
        if {$c < $prev} { set order 0; incr inv }
        set prev $c; set wspan [expr {max($wspan, $p90 - $p10)}]
        qc_log [format "slice3 %s row %2d band %4.0f-%4.0f centroid %6.1f y10-90 %4.0f-%4.0f (%3.0f um) x10-90 %3.0f-%3.0f in-band %.3f" \
            $tag $r $a $b $c $p10 $p90 [expr {$p90 - $p10}] $q10 $q90 $adh]
    }
    qc_summary [format "slice3_%s rows_in_order %d inversions %d max_y10_90_um %.0f min_in_band %.3f" $tag $order $inv $wspan $minadh]
}
proc qb3_classes {tag} {
    estimate_parasitics -placement
    set f $::OUT/rpt/slice3_$tag.ends.rpt
    qc_to $f { report_checks -path_delay max -group_count 5000 -endpoint_count 1 -format end }
    set fh [open $f]; set ends [read $fh]; close $fh
    array set w {}
    foreach line [split $ends \n] {
        if {[llength $line] < 4 || ![regexp {(-?[0-9]+\.[0-9]+)\s*(\(VIOLATED\))?\s*$} $line -> sl]} { continue }
        set p [lindex $line 0]
        if {[regexp {g_r_(\d+)__g_c_0__u_pe/} $p -> r]} { set c pe[format %02d $r] } elseif {[regexp {u_lf/} $p]} { set c lane_f } \
            elseif {[regexp {u_lw/} $p]} { set c lane_w } elseif {[regexp {u_(br|dec)|cdr_reg|ctlr_reg} $p]} { set c dec_br } \
            elseif {[regexp {/} $p]} { set c other } else { set c port }
        if {![info exists w($c)] || $sl < $w($c)} { set w($c) $sl }
    }
    qc_summary "slice3_${tag}_class_wns [lmap k [lsort [array names w]] {format %s=%.3f $k $w($k)}]"
}
# PE-row spread metric (results/r5c.md): per PE row the bounding box of the cells of u_core/g_r_<r>__g_c_0__u_pe/
# (full: min / max of the cell boxes; and 10-90 % of the cell centres in x and y)
proc qb5c_spread {tag} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    array set xs {}; array set ys {}; array set bb {}
    foreach i [$blk getInsts] {
        if {![regexp {^u_core/g_r_(\d+)__g_c_0__u_pe/} [$i getName] -> r]} { continue }
        set b [$i getBBox]
        lappend xs($r) [expr {([$b xMin] + [$b xMax]) / 2.0 / $u}]; lappend ys($r) [expr {([$b yMin] + [$b yMax]) / 2.0 / $u}]
        if {![info exists bb($r)]} { set bb($r) [list [$b xMin] [$b yMin] [$b xMax] [$b yMax]] } else {
            lassign $bb($r) a c d e
            set bb($r) [list [expr {min($a, [$b xMin])}] [expr {min($c, [$b yMin])}] [expr {max($d, [$b xMax])}] [expr {max($e, [$b yMax])}]]
        }
    }
    set wmax 0.0; set hmax 0.0; set h90 0.0; set amax 0.0
    foreach r [lsort -integer [array names bb]] {
        lassign $bb($r) a c d e
        set w [expr {($d - $a) / double($u)}]; set h [expr {($e - $c) / double($u)}]
        set lx [lsort -real $xs($r)]; set ly [lsort -real $ys($r)]; set k [llength $lx]
        set x10 [lindex $lx [expr {int(0.1 * $k)}]]; set x90 [lindex $lx [expr {int(0.9 * $k)}]]
        set y10 [lindex $ly [expr {int(0.1 * $k)}]]; set y90 [lindex $ly [expr {int(0.9 * $k)}]]
        set wmax [expr {max($wmax, $w)}]; set hmax [expr {max($hmax, $h)}]; set h90 [expr {max($h90, $y90 - $y10)}]
        set amax [expr {max($amax, $w * $h)}]
        qc_log [format "r5c spread %s row %2d cells %5d bbox x %5.1f-%5.1f y %6.1f-%6.1f (%5.1f x %5.1f um) x10-90 %5.1f-%5.1f y10-90 %6.1f-%6.1f (%4.0f um)" \
            $tag $r $k [expr {$a / double($u)}] [expr {$d / double($u)}] [expr {$c / double($u)}] [expr {$e / double($u)}] $w $h $x10 $x90 $y10 $y90 [expr {$y90 - $y10}]]
    }
    qc_summary [format "r5c_spread_%s max_bbox_w_um %.1f max_bbox_h_um %.1f max_y10_90_um %.1f max_bbox_area_um2 %.0f" $tag $wmax $hmax $h90 $amax]
}
proc qb5c_status {st} {
    set n 0
    foreach i [[ord::get_db_block] getInsts] {
        if {[string match u_core/g_r_*__g_c_0__u_pe/* [$i getName]]} { $i setPlacementStatus $st; incr n }
    }
    qc_log "r5c: $n PE cells -> $st"
}
proc qb5c_tile {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set dir [qb_env QB_TILE_DIR $::QC_BUILD/pnr]
    set rh [[[lindex [$blk getRows] 0] getSite] getHeight]
    array set rowor {}
    foreach rw [$blk getRows] { set rowor([lindex [$rw getOrigin] 1]) [$rw getOrient] }
    set tot 0; set miss 0; set bad 0
    for {set r 0} {$r < 16} {incr r} {
        lassign [qb_row_y $r] a b
        set k [expr {int(ceil(($a - $::QB_Y0) * $u / double($rh) - 1e-6))}]
        if {$k % 2} { incr k }
        set dy [expr {round($::QB_Y0 * $u) + $k * $rh}]
        set dx [expr {round($::QB_X0 * $u)}]
        set fh [open $dir/r5c_t$r/tile.txt]; set n 0; set ymax 0
        while {[gets $fh line] >= 0} {
            lassign $line nm x y o
            set i [$blk findInst "u_core/g_r_${r}__g_c_0__u_pe/$nm"]
            if {$i eq "NULL" || $i eq ""} { incr miss; continue }
            $i setOrient $o
            $i setLocation [expr {$x + $dx}] [expr {$y + $dy}]
            $i setPlacementStatus FIRM
            if {[info exists rowor([expr {$y + $dy}])] && $rowor([expr {$y + $dy}]) ne $o} { incr bad }
            set ymax [expr {max($ymax, $y + $dy + [[$i getMaster] getHeight])}]
            incr n
        }
        close $fh
        incr tot $n
        qc_log [format "r5c tile row %2d: %d cells at x %.1f y %.1f-%.1f (band %.1f-%.1f)" $r $n [expr {$dx / double($u)}] \
            [expr {$dy / double($u)}] [expr {$ymax / double($u)}] $a $b]
    }
    set left 0
    foreach i [$blk getInsts] {
        if {[string match u_core/g_r_*__g_c_0__u_pe/* [$i getName]] && [$i getPlacementStatus] ne "FIRM"} { incr left }
    }
    qc_summary "r5c_tile cells $tot template_not_in_column $miss pe_cells_not_tiled $left row_orient_mismatch $bad"
}
qb3_seed
rename global_placement qb3_gpl_orig
proc global_placement {args} {
    qb5c_tile
    qb5c_spread tile
    set t [clock seconds]
    qb3_gpl_orig {*}$args
    qc_log "slice3: global placement [expr {[clock seconds] - $t}] s"
    qb3_stats gpl
    qb5c_status PLACED
}
rename detailed_placement qb3_dpl_orig
proc detailed_placement {args} {
    rename detailed_placement {}
    rename qb3_dpl_orig detailed_placement
    qb5c_status FIRM
    set t [clock seconds]
    qb3_gpl_orig -incremental -density 0.8
    qc_log "r5c: incremental global placement (PE cells FIRM) after the DRV repair [expr {[clock seconds] - $t}] s"
    qb5c_status PLACED
    set t [clock seconds]
    detailed_placement {*}$args
    qc_log "slice3: detailed placement [expr {[clock seconds] - $t}] s"
    qb3_stats dpl
    qb3_classes dpl
    qb5c_spread dpl
}
