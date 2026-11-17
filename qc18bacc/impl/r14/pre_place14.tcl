# PRE_PLACE_TCL of impl/r14/top14.cfg.  Root-cause scoping of the place-step DRV repair (results/r14.md section 3):
# a net whose terminals are ALL hard-block pins (abutted column / hub / act edges, and the hub -> column t2 nets that can
# only run on M8 over the 3.1-mm array) has no legal repeater site anywhere along any route: R11's repair put its
# buffers on the pins / Steiner points inside the block footprints (no rows) -> DPL diamond search / failure.  Those
# nets are block interface nets (slew = the blocks' pin drivers + the M8 wire; checked after GRT with GRT parasitics,
# impl/r14/drv_post.tcl), so they are set dont_touch for the placement-parasitics repair (which estimates every wire
# with the M3 RC, QC_PNR_EST_SIGNAL).  Everything with a top std cell / chip IO terminal stays under repair.
# impl/r5b/pre_place.tcl (max transition 0.4, remove_buffers, gpl_incr) runs first.
source $::QB_R5B/pre_place.tcl
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
