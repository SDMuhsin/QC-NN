# PRE_PLACE_TCL of slice3.cfg (results/pnr_slice3.md): placement control of the PE rows of the column strip.
# Seed as slice_place.tcl (every class in a small box at the centre of its band, slice_bands.tcl), then QB_PM:
#   seed    (b) gpl from the band seed (-skip_initial_place) with the density penalty of QB_GPL_ARGS (slice v2 = default)
#   region  (a) every PE row r is a power-domain group whose region is its band (gpl builds one PlacerBase /
#           NesterovBase per power-domain group in this build); QB_REG_LANE 1: the lane band (lanes, parameter banks,
#           other) is a region too; QB_REG_OV um: band overlap of the regions; QB_REG_KEEP 0 (default): the regions are
#           removed after gpl (legalisation / repair then work on the flat strip)
#   remap   (c) gpl as `seed`, then every PE row's cells are mapped into its band by y rank (x and the y order inside
#           the row kept: y' = band_lo + (rank + 0.5) / N x band height), then DRV repair + legalisation only
#   script  (c') no gpl: the seed (PE row r spread uniformly over its band, lanes over the lane band) is legalised
# Logs after gpl and after the first detailed placement (qb3_stats): per PE row placed centroid, 10-90 % y span,
# fraction within its band +- 0.25 band, monotone order; after detailed placement also the worst slack per class.
source $::QB_DIR/slice_bands.tcl
qb_bands
set ::QB_PM [qb_env QB_PM seed]
# QB_BRG: PE rows per broadcast register of the netlist (qb_core BRG; qb_col_cwfp_b2: 2); BR g is seeded between its rows
set ::QB_BRG [qb_env QB_BRG 8]
proc qb3_seed {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    expr {srand(908)}
    set xc [expr {($::QB_X0 + $::QB_X1) / 2.0}]
    set full [expr {$::QB_PM eq "script"}]
    set wx [expr {$full ? 0.48 * ($::QB_X1 - $::QB_X0) : 0.15 * ($::QB_X1 - $::QB_X0)}]
    set f [expr {$full ? 0.48 : 0.15}]
    array set cnt {}
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isCore] || [$i isFixed]} { continue }
        set c [qb_class [$i getName]]
        switch -glob -- $c {
            pe*   { lassign [qb_row_y [string range $c 2 end]] a b; set yc [expr {($a + $b) / 2.0}]; set wy [expr {$f * $::QB_HP}] }
            br*   { set g [string range $c 2 end]; lassign [qb_row_y [expr {$::QB_BRG * $g + $::QB_BRG / 2 - 1}]] a yc; set wy [expr {0.15 * $::QB_HP}] }
            dec   { if {$::QB_HD > 0} { set yc [expr {$::QB_Y1 - $::QB_HD / 2.0}]; set wy [expr {0.3 * $::QB_HD}] } else { lassign [qb_row_y 7] a yc; set wy [expr {0.15 * $::QB_HP}] } }
            default { set yc [expr {$::QB_Y0 + $::QB_HL / 2.0}]; set wy [expr {$f * $::QB_HL}] }
        }
        set x [expr {$xc + (rand() - 0.5) * 2 * $wx}]
        set y [expr {$yc + (rand() - 0.5) * 2 * $wy}]
        $i setLocation [expr {int($x * $u)}] [expr {int($y * $u)}]
        $i setPlacementStatus PLACED
        incr cnt($c)
    }
    qc_log "slice3 seed ($::QB_PM): [lmap k [lsort -dictionary [array names cnt]] {string cat $k = $cnt($k)}]"
}
proc qb3_regions {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set ov [qb_env QB_REG_OV 0.0]
    set x0 [expr {round($::QB_X0 * $u)}]; set x1 [expr {round($::QB_X1 * $u)}]
    set ::QB3_REG {}
    for {set r 0} {$r < 16} {incr r} {
        lassign [qb_row_y $r] a b
        set reg [odb::dbRegion_create $blk qb3_r$r]
        odb::dbBox_create $reg $x0 [expr {round(max($::QB_Y0, $a - $ov) * $u)}] $x1 [expr {round(min($::QB_Y1, $b + $ov) * $u)}]
        set grp [odb::dbGroup_create $blk qb3_g$r]
        $reg addGroup $grp
        set pd [odb::dbPowerDomain_create $blk qb3_pd$r]
        $pd setGroup $grp
        set G(pe$r) $grp; set R(pe$r) $reg
        lappend ::QB3_REG [list $reg $grp $pd]
    }
    if {[qb_env QB_REG_LANE 0]} {
        set reg [odb::dbRegion_create $blk qb3_rl]
        odb::dbBox_create $reg $x0 [expr {round($::QB_Y0 * $u)}] $x1 [expr {round(($::QB_Y0 + $::QB_HL + $ov) * $u)}]
        set grp [odb::dbGroup_create $blk qb3_gl]; $reg addGroup $grp
        set pd [odb::dbPowerDomain_create $blk qb3_pdl]; $pd setGroup $grp
        set G(lane) $grp; set G(other) $grp; set R(lane) $reg; set R(other) $reg
        lappend ::QB3_REG [list $reg $grp $pd]
    }
    array set n {}
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isCore]} { continue }
        set c [qb_class [$i getName]]
        if {[info exists G($c)]} { $G($c) addInst $i; if {[qb_env QB_REG_DPL 0]} { $R($c) addInst $i }; incr n($c) }
    }
    qc_log "slice3 regions: [llength $::QB3_REG] power-domain groups, members [lmap k [lsort -dictionary [array names n]] {string cat $k = $n($k)}]"
}
proc qb3_unregions {} {
    foreach t $::QB3_REG {
        lassign $t reg grp pd
        foreach i [$grp getInsts] { $grp removeInst $i }
        foreach i [$reg getRegionInsts] { $reg removeInst $i }
        odb::dbPowerDomain_destroy $pd
        odb::dbGroup_destroy $grp
        odb::dbRegion_destroy $reg
    }
    set ::QB3_REG {}
    qc_log "slice3 regions removed"
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
qb3_seed
if {$::QB_PM eq "region"} { qb3_regions }
rename global_placement qb3_gpl_orig
proc global_placement {args} {
    if {$::QB_PM eq "script"} {
        qc_log "slice3: global placement skipped (QB_PM script)"
    } elseif {[qb_env QB_GPL_FROM ""] ne ""} {
        # QB_GPL_FROM <file>: cell locations of an earlier identical gpl (QB_GPL_DUMP) instead of running it again
        set blk [ord::get_db_block]; set fh [open [qb_env QB_GPL_FROM ""]]; set n 0
        while {[gets $fh line] >= 0} { lassign $line nm x y; set i [$blk findInst $nm]; if {$i ne "NULL" && $i ne ""} { $i setLocation $x $y; incr n } }
        close $fh
        qc_log "slice3: global placement read from [qb_env QB_GPL_FROM {}] ($n cells)"
    } else {
        set t [clock seconds]
        # QB_NESV_ITER: cap on the Nesterov iterations (region diagnosis: the region PlacerBases never converge)
        if {[qb_env QB_NESV_ITER 0] > 0} { gpl::set_nesv_place_iter_cmd [qb_env QB_NESV_ITER 0] }
        qb3_gpl_orig {*}$args
        qc_log "slice3: global placement [expr {[clock seconds] - $t}] s"
        if {[qb_env QB_GPL_DUMP ""] ne ""} {
            set fh [open [qb_env QB_GPL_DUMP ""] w]
            foreach i [[ord::get_db_block] getInsts] { if {[[$i getMaster] isCore] && ![$i isFixed]} { puts $fh "[list [$i getName]] [$i getLocation]" } }
            close $fh
        }
    }
    qb3_stats gpl
    if {$::QB_PM eq "region" && ![qb_env QB_REG_KEEP 0]} { qb3_unregions }
    if {$::QB_PM eq "remap"} {
        set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
        array set mem {}
        foreach i [$blk getInsts] {
            if {[regexp {^u_core/g_r_(\d+)__g_c_0__u_pe/} [$i getName] -> r]} { lappend mem($r) [list $i [lindex [$i getLocation] 1]] }
        }
        for {set r 0} {$r < 16} {incr r} {
            lassign [qb_row_y $r] a b
            set l [lsort -integer -index 1 $mem($r)]; set k [llength $l]; set j 0
            foreach e $l {
                set i [lindex $e 0]; lassign [$i getLocation] x y
                $i setLocation $x [expr {round(($a + ($j + 0.5) / $k * ($b - $a)) * $u - [[$i getMaster] getHeight] / 2.0)}]
                incr j
            }
            # QB_REMAP_X 1: x by rank too (uniform over the strip width; gpl left the rows 60-200 um wide in x, so the
            # y-only remap overfills the band locally: qcs3_remap legalisation +56 % HPWL, max displacement 328 um)
            if {[qb_env QB_REMAP_X 0]} {
                set l {}; foreach e $mem($r) { lappend l [list [lindex $e 0] [lindex [[lindex $e 0] getLocation] 0]] }
                set l [lsort -integer -index 1 $l]; set j 0
                foreach e $l {
                    set i [lindex $e 0]; lassign [$i getLocation] x y
                    $i setLocation [expr {round(($::QB_X0 + ($j + 0.5) / $k * ($::QB_X1 - $::QB_X0)) * $u - [[$i getMaster] getWidth] / 2.0)}] $y
                    incr j
                }
            }
        }
        # QB_REMAP_BR 1: the broadcast register of group g and the decoders / CREG port registers keep their gpl spread
        # but are shifted so that their centroid sits where the seed put them (centre of rows 8g .. 8g + 7 / row 7-8
        # boundary): gpl placed them relative to the scrambled rows
        if {[qb_env QB_REMAP_BR 0]} {
            array set cm {}
            foreach i [$blk getInsts] {
                set c [qb_class [$i getName]]
                if {[string match br* $c] || $c eq "dec"} { lappend cm($c) $i }
            }
            foreach c [array names cm] {
                if {$c eq "dec"} { if {$::QB_HD > 0} { set yt [expr {$::QB_Y1 - $::QB_HD / 2.0}] } else { lassign [qb_row_y 7] a yt } } else { lassign [qb_row_y [expr {$::QB_BRG * [string range $c 2 end] + $::QB_BRG / 2 - 1}]] a yt }
                set s 0.0; foreach i $cm($c) { set s [expr {$s + [lindex [$i getLocation] 1]}] }
                set dy [expr {round($yt * $u - $s / [llength $cm($c)])}]
                foreach i $cm($c) { lassign [$i getLocation] x y; $i setLocation $x [expr {$y + $dy}] }
                qc_log [format "slice3 remap: %s (%d cells) shifted by %.0f um" $c [llength $cm($c)] [expr {$dy / double($u)}]]
            }
        }
        qb3_stats remap
        # QB_REMAP_INC 1: incremental global placement from the remapped (ordered, nearly spread) placement
        if {[qb_env QB_REMAP_INC 0]} {
            set t [clock seconds]
            qb3_gpl_orig -incremental -density [p PLACE_DENSITY] {*}[qb_env QB_INC_ARGS {}]
            qc_log "slice3: incremental global placement [expr {[clock seconds] - $t}] s"
            qb3_stats inc
        }
        # QB_REMAP_GPL <gpl args>: a second global placement from the remapped placement (with QB_REMAP_X 1 it is
        # spread over every band, so a high initial density penalty keeps cells near their remapped place while the
        # wirelength / timing forces act locally)
        if {[qb_env QB_REMAP_GPL ""] ne ""} {
            set t [clock seconds]
            qb3_gpl_orig {*}[qb_env QB_REMAP_GPL ""]
            qc_log "slice3: second global placement [expr {[clock seconds] - $t}] s"
            qb3_stats gpl2
        }
    }
}
rename detailed_placement qb3_dpl_orig
proc detailed_placement {args} {
    rename detailed_placement {}
    rename qb3_dpl_orig detailed_placement
    # QB_INC_POST 1: incremental global placement after the DRV repair, before this first legalisation (qcs3_b2: the
    # repair grows the cell area +13 % where the violating nets are, local utilisation 0.95-0.97 after CTS around PE
    # rows 6 / 7, and the CTS / post-CTS legalisations then move the S2 accumulator cells 130-150 um)
    if {[qb_env QB_INC_POST 0]} {
        set t [clock seconds]
        qb3_gpl_orig -incremental -density [qb_env QB_INC_DENS 0.85]
        qc_log "slice3: incremental global placement after the DRV repair [expr {[clock seconds] - $t}] s"
        qb3_stats incpost
    }
    set t [clock seconds]
    # QB_DPL1_ARGS: arguments of this first legalisation (remap: the bands of the upper rows also hold decoder / BR /
    # DRV-buffer cells, so the default displacement window fails with DPL-0036)
    detailed_placement {*}[qb_env QB_DPL1_ARGS $args]
    qc_log "slice3: detailed placement [expr {[clock seconds] - $t}] s"
    qb3_stats dpl
    qb3_classes dpl
}
