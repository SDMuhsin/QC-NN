# PRE_PLACE_TCL of impl/r14/top14.cfg.  Root-cause scoping of the place-step DRV repair (results/r14.md section 3):
# a net whose terminals are ALL hard-block pins (abutted column / hub / act edges, and the hub -> column t2 nets that can
# only run on M8 over the 3.1-mm array) has no legal repeater site anywhere along any route: R11's repair put its
# buffers on the pins / Steiner points inside the block footprints (no rows) -> DPL diamond search / failure.  Those
# nets are block interface nets (slew = the blocks' pin drivers + the M8 wire; checked after GRT with GRT parasitics,
# impl/r14/drv_post.tcl), so they are set dont_touch for the placement-parasitics repair (which estimates every wire
# with the M3 RC, QC_PNR_EST_SIGNAL).  Everything with a top std cell / chip IO terminal stays under repair.
# impl/r5b/pre_place.tcl (max transition 0.4, remove_buffers, gpl_incr) runs first.
source $::QB_R5B/pre_place.tcl
# R39 opt-in QB39_DPLPAD <sites> [0]: detailed-placement padding (set_placement_padding -global) for every later DPL;
# gpl's -pad_* only spread the global placement, DPL then legalised gpl's early-stop clumps at up to 100 % (r39_y bins)
# R39 opt-in QB39_HUBHALO "<h_um> <w_um>": hard placement blockage h um high above the hub's top edge, from the hub's
# west end w um long (the edge part facing the gap: ~5.6 k pins at 0.4-um pitch on M2 / M4 / M6, r39_y DR it1: 39 %
# of all markers in the 200 um at the u_top_pt pins, std cells packed right against the edge)
if {[llength [qb_env QB39_HUBHALO ""]] == 2} {
    lassign [qb_env QB39_HUBHALO ""] _h _w
    set _b [ord::get_db_block]; set _u [$_b getDefUnits]
    foreach _i [$_b getInsts] {
        if {[[$_i getMaster] getName] ne "qb_hub"} continue
        set _bb [$_i getBBox]
        set _bl [odb::dbBlockage_create $_b [$_bb xMin] [$_bb yMax] [expr {[$_bb xMin] + int($_w * $_u)}] [expr {[$_bb yMax] + int($_h * $_u)}]]
        qc_log "r39: hub halo blockage [expr {[$_bb xMin] / double($_u)}] [expr {[$_bb yMax] / double($_u)}] +$_w x +$_h um"
    }
}
if {[qb_env QB39_DPLPAD 0] > 0} { set_placement_padding -global -left [qb_env QB39_DPLPAD 0] -right [qb_env QB39_DPLPAD 0]; qc_log "r39: DPL padding [qb_env QB39_DPLPAD 0] sites" }
# (after remove_buffers: DC buffers between two block pins, e.g. 32 hub -> column t2 nets, make them block-only)
set _n 0; set _nb 0; set _l {}
foreach net [[ord::get_db_block] getNets] {
    if {[$net getSigType] ne "SIGNAL"} { continue }
    if {[llength [$net getBTerms]]} { continue }
    set its [$net getITerms]
    if {[llength $its] < 2} { continue }
    set blk 1
    foreach t $its { if {[lsearch -exact {qb_col_blk qb_hub qb_act2_blk} [[[$t getInst] getMaster] getName]] < 0} { set blk 0; break } }
    if {$blk} { lappend _l [$net getName]; incr _nb }
    incr _n
}
if {[llength $_l]} { set_dont_touch [get_nets $_l] }
qc_log "r14 pre_place: $_nb block-only signal nets (of $_n) dont_touch for the placement-parasitics DRV repair"
# channel-end repeaters (split14.tcl) after global placement, before the DRV repair (wraps qc_repair_drv, after
# gpl_incr's wrapper): FIRM during the incremental gpl, PLACED for the final detailed placement.
if {[qb_env QB14_SPLIT 1] && [info commands q14_drv_inner] eq ""} {
    source $::QB_R14/split14.tcl
    rename qc_repair_drv q14_drv_inner
    proc qc_repair_drv {} {
        q14s_split
        estimate_parasitics -placement
        q14_drv_inner
        q14s_release
    }
}
