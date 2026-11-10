# Partial placement blockages (max density P(QA_CH_DENS) %) over the channels between the macro rows (act tiers and
# weight / param tiers), sourced by xbar_place.tcl when P(QA_CH_DENS) > 0.  Without them (qa4_u1, qa4_u2) global
# placement puts parts of the head (u_head pfd / prod / fifo registers, y 2.58-3.04 mm) and the param-memory logic
# into the 40-um channels next to the top weight tier, strung over ~0.5 mm: D0 / D1 cells drive 0.05-0.18 pF and
# the post-CTS tt path u_head/pfd -> prod is -3.6 ns.  The channels keep room for the act-macro pin logic (input
# flops, output registers: ~6 % of a channel).
# P(QA_EDGE_DENS) % > 0: also a partial blockage of P(QA_EDGE_W) um (default 120) along both macro edges of the logic
# band: in qa4_u2 / qa4_t3 global placement left its residual overflow there (cells piled against the act-macro rows,
# 50-150 um deep, 95-100 % utilisation over the whole band width).
set blk [ord::get_db_block]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set iv {}
foreach i [$blk getInsts] {
    if {![[$i getMaster] isBlock]} { continue }
    set b [$i getBBox]
    lappend iv [list [$b yMin] [$b yMax]]
}
# merge macro y intervals into rows
set iv [lsort -integer -index 0 $iv]
set rows {}
foreach r $iv {
    if {[llength $rows] && [lindex $rows end 1] >= [lindex $r 0]} {
        lset rows end 1 [expr {max([lindex $rows end 1], [lindex $r 1])}]
    } else { lappend rows $r }
}
set die [$blk getDieArea]
set band 0; set nb 0
for {set k 1} {$k < [llength $rows]} {incr k} {
    set g [expr {[lindex $rows $k 0] - [lindex $rows [expr {$k - 1}] 1]}]
    if {$g > $band} { set band $g }
}
for {set k 1} {$k < [llength $rows]} {incr k} {
    set y0 [lindex $rows [expr {$k - 1}] 1]; set y1 [lindex $rows $k 0]
    if {$y1 - $y0 == $band} {
        if {[p QA_EDGE_DENS 0] > 0} {
            set w [expr {round([p QA_EDGE_W 120.0] * $u)}]
            foreach {e0 e1} [list $y0 [expr {$y0 + $w}] [expr {$y1 - $w}] $y1] {
                set bl [odb::dbBlockage_create $blk [$die xMin] $e0 [$die xMax] $e1]
                $bl setMaxDensity [p QA_EDGE_DENS]
                qc_log [format "ch_block: band edge y %.1f-%.1f max density %s %%" [expr {$e0 / double($u)}] [expr {$e1 / double($u)}] [p QA_EDGE_DENS]]
            }
        }
        continue
    }
    if {[p QA_CH_DENS 0] <= 0} { continue }
    set bl [odb::dbBlockage_create $blk [$die xMin] $y0 [$die xMax] $y1]
    $bl setMaxDensity [p QA_CH_DENS]
    incr nb
    qc_log [format "ch_block: channel y %.1f-%.1f max density %s %%" [expr {$y0 / double($u)}] [expr {$y1 / double($u)}] [p QA_CH_DENS]]
}
qc_log "ch_block: $nb partial blockages"
