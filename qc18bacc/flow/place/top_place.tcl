# PRE_PLACE_TCL of blocks/top/top.cfg (results/r14.md section 3, r39.md, r43.md).
#   1. place/rm_buffers.tcl: max transition 0.4, remove_buffers, incremental gpl + DRV repair (place/gpl_incr.tcl)
#   2. hub keep-out ::QB_HUBHALO {h w} (top.cfg): the strip h um high above the hub's top edge, from the hub's west end w
#      um long (the edge part facing the gap: ~5.6 k pins at 0.4-um pitch on M2 / M4 / M6, r39_y DR it1: 39 % of all
#      markers in the 200 um at the u_top_pt pins).  OR 2.0-12381 gpl / DPL / check_placement ignore a dbBlockage (1 645
#      cells sat in it on r39_v), so the rows under it are removed and every later check_placement fails on an instance
#      inside it (place/keepout.tcl, R43)
#   3. detailed-placement padding 2 sites (set_placement_padding -global) for every later DPL: gpl's -pad_* only spread the
#      global placement, DPL then legalised gpl's early-stop clumps at up to 100 % (r39_y bins)
#   4. root-cause scoping of the place-step DRV repair: a net whose terminals are ALL hard-block pins (abutted column /
#      hub / act edges, and the hub -> column t2 nets that can only run on M8 over the 3.1-mm array) has no legal
#      repeater site anywhere along any route (R11: buffers inside the block footprints -> DPL diamond search / failure).
#      Those block interface nets are set dont_touch for the placement-parasitics repair (checked after GRT with GRT
#      parasitics, route/top_drv_post.tcl); everything with a top std cell / chip IO terminal stays under repair.
#   5. channel-end repeaters (place/top_split.tcl) after global placement, before the DRV repair (wraps qc_repair_drv,
#      after gpl_incr's wrapper): FIRM during the incremental gpl, PLACED for the final detailed placement.
source $::QBF/place/rm_buffers.tcl
lassign $::QB_HUBHALO _h _w
set _b [ord::get_db_block]; set _u [$_b getDefUnits]
foreach _i [$_b getInsts] {
    if {[[$_i getMaster] getName] ne "qb_hub"} continue
    set _bb [$_i getBBox]
    set _ko [list [$_bb xMin] [$_bb yMax] [expr {[$_bb xMin] + int($_w * $_u)}] [expr {[$_bb yMax] + int($_h * $_u)}]]
    source $::QBF/place/keepout.tcl
    q43_keepout {*}$_ko
    qc_log "r39: hub halo rows removed [expr {[$_bb xMin] / double($_u)}] [expr {[$_bb yMax] / double($_u)}] +$_w x +$_h um"
}
set_placement_padding -global -left 2 -right 2; qc_log "r39: DPL padding 2 sites"
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
if {[info commands q14_drv_inner] eq ""} {
    source $::QBF/place/top_split.tcl
    rename qc_repair_drv q14_drv_inner
    proc qc_repair_drv {} {
        q14s_split
        estimate_parasitics -placement
        q14_drv_inner
        q14s_release
    }
}
