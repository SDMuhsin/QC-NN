# PDN_TCL of blocks/top/top.cfg (results/r36.md): floorplan/pdn_chip.tcl with chip-level PG pins, so that
# check_power_grid has voltage sources (R35a bug 2: PSM-0014 on the top, the grid check never ran).  The core grid gets
# -pins M9 and the M9 straps -extend_to_boundary: VDD / VSS bterms where the M9 straps meet the die edge (west / east),
# i.e. the chip's supply inputs.
set ::QB36_PGL M9
rename define_pdn_grid qb36_dpg_orig
proc define_pdn_grid {args} {
    if {[lsearch -exact $args -macro] < 0 && [lsearch -exact $args -name] >= 0 && [lindex $args [expr {[lsearch -exact $args -name] + 1}]] eq "core"} {
        lappend args -pins $::QB36_PGL; qc_log "r36: core grid pins $::QB36_PGL"
    }
    uplevel 1 [list qb36_dpg_orig {*}$args]
}
rename add_pdn_stripe qb36_aps_orig
proc add_pdn_stripe {args} {
    set i [lsearch -exact $args -layer]
    if {$i >= 0 && [lindex $args [expr {$i + 1}]] eq $::QB36_PGL && [lsearch -exact $args -extend_to_boundary] < 0} { lappend args -extend_to_boundary }
    uplevel 1 [list qb36_aps_orig {*}$args]
}
source $::QBF/floorplan/pdn_chip.tcl
rename define_pdn_grid {}; rename qb36_dpg_orig define_pdn_grid
rename add_pdn_stripe {}; rename qb36_aps_orig add_pdn_stripe
# R35a bug 3 (results/r36.md sec. 2): pdngen cuts the core-grid M7 (and lower) straps at the block
# LEF obstructions and keeps the fragments in the gaps of the blocks' exact M7 shapes, with via stacks to the M8
# straps: top metal inside the block area that is not on a block PG pin (it shorts block wiring as soon as the block
# view is not the final one, and is never needed).  After pdngen: every special-net shape / via on routing level
# <= 7 that overlaps a hard block (qb_col_blk / qb_hub / qb_act2_blk) is removed unless it lies inside a same-net PG pin
# rect of that block (the intended M7 -> M8 connections).
set ::QB36_CLEANM {qb_col_blk qb_hub qb_act2_blk}
proc qb36_pg_clean {} {
    set blk [ord::get_db_block]; set lvl 7
    set regs {}; array set pin {}
    foreach i [$blk getInsts] {
        set m [$i getMaster]; if {[$m getName] ni $::QB36_CLEANM} { continue }
        if {[$i getOrient] ne "R0"} { qc_log "r36 pgclean: [$i getName] orient [$i getOrient] not handled"; continue }
        set bb [$i getBBox]; lassign [$i getLocation] ox oy
        lappend regs [list [$bb xMin] [$bb yMin] [$bb xMax] [$bb yMax]]
        foreach mt [$m getMTerms] {
            set st [$mt getSigType]; if {$st ne "POWER" && $st ne "GROUND"} { continue }
            set net [expr {$st eq "POWER" ? $::QC_PNR_PWR : $::QC_PNR_GND}]
            foreach mp [$mt getMPins] { foreach g [$mp getGeometry] {
                set l [$g getTechLayer]; if {$l eq "NULL"} { continue }
                set r [list [expr {[$g xMin]+$ox}] [expr {[$g yMin]+$oy}] [expr {[$g xMax]+$ox}] [expr {[$g yMax]+$oy}]]
                for {set k [expr {[lindex $r 1] / 20000}]} {$k <= [lindex $r 3] / 20000} {incr k} { lappend pin($net,[$l getName],$k) $r }
            } }
        }
    }
    set kill 0; set keep 0
    foreach net [list $::QC_PNR_PWR $::QC_PNR_GND] {
        set n [$blk findNet $net]; if {$n eq "NULL"} { continue }
        foreach sw [$n getSWires] { foreach w [$sw getWires] {
            set r [list [$w xMin] [$w yMin] [$w xMax] [$w yMax]]
            set in 0; foreach g $regs { if {[lindex $r 0] < [lindex $g 2] && [lindex $g 0] < [lindex $r 2] && [lindex $r 1] < [lindex $g 3] && [lindex $g 1] < [lindex $r 3]} { set in 1; break } }
            if {!$in} { continue }
            if {[$w isVia]} {
                set v [expr {[$w getTechVia] ne "NULL" ? [$w getTechVia] : [$w getBlockVia]}]
                set l [$v getBottomLayer]
                # the bottom enclosure of the via
                set xy [$w getViaXY]; set e {}
                foreach b [$v getBoxes] { if {[$b getTechLayer] eq $l} { set e [list [expr {[lindex $xy 0]+[$b xMin]}] [expr {[lindex $xy 1]+[$b yMin]}] [expr {[lindex $xy 0]+[$b xMax]}] [expr {[lindex $xy 1]+[$b yMax]}]] } }
                if {$e ne ""} { set r $e }
            } else { set l [$w getTechLayer] }
            if {[$l getRoutingLevel] == 0 || [$l getRoutingLevel] > $lvl} { continue }
            set ok 0
            foreach k [list [expr {[lindex $r 1] / 20000}]] {
                if {![info exists pin($net,[$l getName],$k)]} { continue }
                foreach p $pin($net,[$l getName],$k) {
                    if {[lindex $p 0] <= [lindex $r 0] && [lindex $p 1] <= [lindex $r 1] && [lindex $p 2] >= [lindex $r 2] && [lindex $p 3] >= [lindex $r 3]} { set ok 1; break }
                }
                if {$ok} { break }
            }
            if {$ok} { incr keep } else { odb::dbSBox_destroy $w; incr kill }
        } }
    }
    qc_log "r36 pgclean: removed $kill special shapes / vias (level <= $lvl) over [llength $regs] hard blocks, kept $keep on block PG pins"
    qc_summary "r36 pgclean removed $kill kept $keep"
}
if {[info commands qb36_pdngen_orig] eq ""} {
    rename pdngen qb36_pdngen_orig
    proc pdngen {args} {
        # top M8 straps over a block with M9 PG pins (hub) get VIA8 to them.  Without the M7 fragments
        # (removed below) the M8 straps over the hub's east part (no hub M7 PG pins there) are otherwise only joined
        # through the hub's internal grid, which check_power_grid cannot see (PSM-0069).
        catch { add_pdn_connect -grid macro_blk -layers {M8 M9} }
        uplevel 1 [list qb36_pdngen_orig {*}$args]; qb36_pg_clean
    }
}
