# PRE_PLACE_TCL of QC18-ACC v4 (qa4b.cfg): rows_fix.tcl, then structured placement of the distributed activation
# crossbar (results/pnr_v4.md section 2).  Without it, global placement of qa4.cfg (qa4_u1) pulls every xbar stage
# to the centre of the band: the 16 x 128 bank-select registers (u_act/ar_rdata), stage A (u_xbar/sa) and window
# (u_xbar/win) registers all land in a ~350 x 400 um hub at 95-100 % cell utilisation, and the per-macro output
# registers follow them into the macro-row channels at x 1.0-2.3 mm (bank 0's 128-b Q bus runs ~1.2 mm along a
# 40-um channel): a pipeline of registers is a chain of 2-pin nets whose wire length does not depend on where along
# the path each stage sits, so the density term alone decides, and it loses to the hub's connectivity.
# Here the stage registers are placed FIRM before global placement (gpl treats them as fixed), each group packed into
# a compact block at its target, on legal sites:
#   bank-select k (128 flops):  band edge under bank k's macro column (top banks 0-7, bottom 15-8, macro_place4.tcl)
#   stage A slot i (128):       centroid of its source banks i..i+3 (mod 16) on that ring, QA_XB_INSET um into the band
#   window row j (128):         a 8 x 2 grid over the PE part of the band (QA_XB_WX0..WX1, y QA_XB_WY), rows of shadow
#                               chain A (bit 1 of j = 0) in the lower half, chain B in the upper half, j descending in x
# Right after global placement (global_placement is wrapped here) xbar_unfix.tcl turns them back to PLACED, so the
# DRV repair may resize them and detailed placement legalises them with everything else (left FIRM, the resized
# registers overlapped their packed neighbours: DPL-0033, 4 408 overlaps).
source [file normalize $::env(QC_FLOW)/../../qc18acc/pnr]/rows_fix.tcl
if {[p QA_CH_DENS 0] > 0 || [p QA_EDGE_DENS 0] > 0} { source [file normalize $::env(QC_FLOW)/../../qc18acc/pnr]/ch_block.tcl }
set blk [ord::get_db_block]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
proc qa_um {v} { return [expr {$v / double($::u)}] }
# macro column centres / band edges
array set colx {}
foreach k {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15} {
    set m [$blk findInst [format {u_act/g_bank_%d__g_buf_0__u_ram/g_mac_g_act_u_mac} $k]]
    set b [$m getBBox]
    set colx($k) [expr {([qa_um [$b xMin]] + [qa_um [$b xMax]]) / 2.0}]
    if {$k < 8} { set ytop [qa_um [$b yMin]] } else { set ybot [qa_um [$b yMax]] }
}
set halo [lindex [p MACRO_HALO] 1]
set ytop [expr {$ytop - $halo}]; set ybot [expr {$ybot + $halo}]
qc_log "xbar_place: band y $ybot - $ytop"
# rows by y
set rows {}
foreach r [$blk getRows] { lappend rows [list [qa_um [lindex [$r getOrigin] 1]] $r] }
set rows [lsort -real -index 0 $rows]
set ::qa_occ {}
# pack insts (list of dbInst) into a block of ncol cells per row, centred at cx, first row nearest cy, going dir (+1 up / -1 down)
proc qa_pack {insts cx cy ncol dir} {
    global rows u
    set best 0; set bd 1e9
    for {set i 0} {$i < [llength $rows]} {incr i} {
        set d [expr {abs([lindex $rows $i 0] - $cy)}]
        if {$d < $bd} { set bd $d; set best $i }
    }
    set n [llength $insts]; set k 0; set ri $best
    while {$k < $n} {
        set r [lindex $rows $ri 1]
        set site [$r getSite]; set sw [$site getWidth]
        lassign [$r getOrigin] rx ry
        set chunk [lrange $insts $k [expr {$k + $ncol - 1}]]
        set w 0; foreach i $chunk { incr w [[$i getMaster] getWidth] }
        set x [expr {round($cx * $u) - $w / 2}]
        set x [expr {$rx + (($x - $rx) / $sw) * $sw}]
        foreach i $chunk {
            $i setOrient [$r getOrient]
            $i setLocation $x $ry
            $i setPlacementStatus FIRM
            incr x [[$i getMaster] getWidth]
        }
        incr k $ncol
        incr ri $dir
    }
}
proc qa_group {fmt lo hi} {
    set l {}
    for {set b $lo} {$b < $hi} {incr b} {
        set i [[ord::get_db_block] findInst [format $fmt $b]]
        if {$i eq "NULL" || $i eq ""} { error "xbar_place: no instance [format $fmt $b]" }
        lappend l $i
    }
    return $l
}
set ncol [p QA_XB_NCOL 32]
set inset [p QA_XB_INSET 40.0]
# bank-select registers: 4 rows x 32 at the band edge of the column
foreach k {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15} {
    set g [qa_group {u_act/ar_rdata_reg_%d_} [expr {$k * 128}] [expr {$k * 128 + 128}]]
    if {$k < 8} { qa_pack $g $colx($k) [expr {$ytop - 3.0}] $ncol -1 } else { qa_pack $g $colx($k) [expr {$ybot + 3.0}] $ncol 1 }
}
# stage A: centroid of the 4 source banks' edge points, moved QA_XB_INSET into the band
for {set i 0} {$i < 16} {incr i} {
    set sx 0.0; set sy 0.0
    for {set d 0} {$d < 4} {incr d} {
        set k [expr {($i + $d) % 16}]
        set sx [expr {$sx + $colx($k)}]
        set sy [expr {$sy + ($k < 8 ? $ytop - $inset : $ybot + $inset)}]
    }
    set g [qa_group {u_xbar/sa_reg_%d_} [expr {$i * 128}] [expr {$i * 128 + 128}]]
    qa_pack $g [expr {$sx / 4.0}] [expr {$sy / 4.0}] $ncol [expr {$sy / 4.0 > ($ytop + $ybot) / 2.0 ? -1 : 1}]
}
# window rows: chain A rows (0 1 4 5 8 9 12 13) in the lower half, chain B (2 3 6 7 10 11 14 15) in the upper half,
# x descending with j (the arrangement global placement chose for the PE rows in qa4_u1)
set wx0 [p QA_XB_WX0 425.0]; set wx1 [p QA_XB_WX1 2175.0]
set wyl [expr {$ybot + [p QA_XB_WYF 0.32] * ($ytop - $ybot)}]
set wyh [expr {$ybot + (1.0 - [p QA_XB_WYF 0.32]) * ($ytop - $ybot)}]
set ia 0; set ib 0
for {set j 0} {$j < 16} {incr j} {
    if {(($j >> 1) & 1) == 0} { set slot $ia; incr ia; set wy $wyl } else { set slot $ib; incr ib; set wy $wyh }
    set wx [expr {$wx1 - $slot * ($wx1 - $wx0) / 7.0}]
    set g [qa_group {u_xbar/win_reg_%d_} [expr {$j * 128}] [expr {$j * 128 + 128}]]
    qa_pack $g $wx $wy $ncol 1
    qc_log [format "xbar_place: window row %d at %.0f %.0f" $j $wx $wy]
}
qc_log "xbar_place: 6144 bank-select / stage-A / window registers placed FIRM"
if {[info commands qa_gpl_orig] eq ""} {
    rename global_placement qa_gpl_orig
    proc global_placement {args} {
        qa_gpl_orig {*}$args
        source [file normalize $::env(QC_FLOW)/../../qc18acc/pnr]/xbar_unfix.tcl
    }
}
