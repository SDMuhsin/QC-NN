# PRE_PLACE_TCL of impl/r5c/col.cfg (results/r5c.md): structured PE placement, flat routing.
#   1. impl/pnr/slice3_place.tcl as R5a (band seed of every cell, gpl / DPL wrappers, per-row statistics)
#   2. tile: the standalone placement of PE row r (impl/r5c/pe_tile.cfg, $QB_TILE_DIR/r5c_t<r>/tile.txt) is copied
#      into PE row r's slot: x from the core's west edge + QB_TILE_X, y from the first even row (same row
#      orientation as the template) at or above the bottom of row r's band (impl/pnr/slice_bands.tcl);
#      the PE cells are FIRM (gpl / DPL treat them as fixed)
#   3. gpl (timing-driven, from the seed) places only the remaining cells (decoders, BRs, feedthrough, lanes, banks)
#   4. PE cells back to PLACED for the DRV repair; before the first legalisation the R5a incremental re-spread
#      (QB_INC_POST, density QB_INC_DENS) runs with the PE cells FIRM again (only repair buffers and non-PE cells
#      move), then PLACED: legalisation, CTS, repair and their legalisations may move PE cells as in R5a
source $::QB_DIR/slice3_place.tcl
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r5c/spread.tcl]
set ::QB5C_INC [qb_env QB_INC_POST 0]
set ::env(QB_INC_POST) 0
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
        set dx [expr {round(($::QB_X0 + [qb_env QB_TILE_X 0.0]) * $u)}]
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
rename global_placement qb5c_gpl_s3
proc global_placement {args} {
    qb5c_tile
    qb5c_spread tile
    qb5c_gpl_s3 {*}$args
    qb5c_status PLACED
}
rename detailed_placement qb5c_dpl_s3
proc detailed_placement {args} {
    rename detailed_placement {}
    rename qb5c_dpl_s3 detailed_placement
    if {$::QB5C_INC} {
        qb5c_status FIRM
        set t [clock seconds]
        qb3_gpl_orig -incremental -density [qb_env QB_INC_DENS 0.85]
        qc_log "r5c: incremental global placement (PE cells FIRM) after the DRV repair [expr {[clock seconds] - $t}] s"
        qb5c_status PLACED
    }
    detailed_placement {*}$args
    qb5c_spread dpl
}
