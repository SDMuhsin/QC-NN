# Macro clock gates before CTS (sourced by xbar_unfix.tcl when P(QA_MACRO_ICG) is set; results/pnr_v4.md section 4).
# Every SRAM / RF macro CLK is driven by its own CKLNQD2 (qa_sram4 g_mac_u_cg) through a 1-sink net that CTS does not
# buffer.  In qa4_t5 (routed, PrimeTime + SPEF) that gate sat up to ~1 mm from its macro: 0.25 pF on the gated clock
# net, 0.78-0.93 ns slew, so the weight-macro CLK arrived at 2.24 ns tt against 1.25 ns at its input flops and the
# hold checks at the macro D / A pins failed by up to -0.33 ns tt / -0.41 ns ss (2 400 tt endpoints, mostly act-macro
# D) although the post-GRT repair (global-route parasitics) had met them.  Here each macro gate is resized to
# P(QA_MACRO_ICG) (default CKLNQD16) and moved next to its macro's CLK pin (the legaliser finds the nearest free site),
# so CTS balances it like any other gate and the gated net is a few um long.
set blk [ord::get_db_block]
set lib_icg [p QA_MACRO_ICG CKLNQD16]
set m_icg [[ord::get_db] findMaster $lib_icg]
if {$m_icg eq "NULL" || $m_icg eq ""} { error "macro_icg: no master $lib_icg" }
set n 0
foreach i [$blk getInsts] {
    if {![[$i getMaster] isBlock]} { continue }
    set ck [$i findITerm CLK]
    if {$ck eq "NULL" || $ck eq ""} { continue }
    set net [$ck getNet]
    if {$net eq "NULL"} { continue }
    set drv ""
    foreach it [$net getITerms] { if {[$it isOutputSignal]} { set drv [$it getInst] } }
    if {$drv eq "" || ![string match CKLNQD* [[$drv getMaster] getName]]} { continue }
    lassign [$ck getAvgXY] ok px py
    if {!$ok} { set b [$i getBBox]; set px [expr {([$b xMin] + [$b xMax]) / 2}]; set py [$b yMin] }
    # put the gate on the band side of the pin: outside the macro (and its halo), toward the logic band centre
    set mb [$i getBBox]
    set halo [expr {round(([lindex [p MACRO_HALO] 1] + 2.0) * [[ord::get_db_tech] getDbUnitsPerMicron])}]
    set dy [expr {$py - ([$mb yMin] + [$mb yMax]) / 2}]
    set gy [expr {$dy >= 0 ? [$mb yMax] + $halo : [$mb yMin] - $halo - [$m_icg getHeight]}]
    if {[info commands replace_cell] ne ""} { replace_cell [$drv getName] $lib_icg } else { $drv swapMaster $m_icg }
    $drv setLocation [expr {$px - [$m_icg getWidth] / 2}] $gy
    $drv setPlacementStatus PLACED
    incr n
}
detailed_placement {*}[p DPL_ARGS]
qc_log "macro_icg: $n macro clock gates -> $lib_icg, moved next to their macro CLK pins"
