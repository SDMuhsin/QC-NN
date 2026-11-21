# R35 stand-in for impl/r9b/post_grt.tcl inside impl/r14/post_grt14.tcl (impl/r35/top.cfg points ::QB_R9B here for the
# POST_GRT step only): timing repair at GRT parasitics (setup, then hold with margin QB35_HOLD_M [0.05]), legalisation,
# incremental GRT (repair_design first, QB35_GRTDRV [1]), then the real impl/r9b/post_grt.tcl (reports, db/grt.odb, exit).  QB35_GRTREP 0: skip the repair.
proc qb35_stat {tag} {
    set s [sta::worst_slack_corner [sta::find_corner tt] max]; set h [sta::worst_slack_corner [sta::find_corner tt] min]
    set ns NA; set nh NA; catch { set ns [sta::endpoint_violation_count max] }; catch { set nh [sta::endpoint_violation_count min] }
    qc_summary [format "r35 %s tt setup_wns_ns %.3f viol %s hold_wns_ns %.3f hold_viol %s %s" $tag [expr {$s*1e9}] $ns [expr {$h*1e9}] $nh [qc_util]]
}
if {[qb_env QB35_GRTREP 1]} {
    set _t [clock seconds]
    # R43 opt-in QB43_AUTOL 1: IO latency re-measured at GRT parasitics after the GRT balancing (impl/r43/autol43_or.tcl)
    if {[qb_env QB43_AUTOL 0]} { source [file normalize $::QB_R35/../r43/autol43_or.tcl]; q43_autol grt }
    qb35_stat grt_pre_repair
    global_route -start_incremental
    if {[qb_env QB35_GRTDRV 1]} {
        if {[catch { repair_design -max_utilization [p MAX_UTIL] } e]} { qc_log "r35: post-GRT repair_design: $e" }
        qb35_stat grt_drv_repair
    }
    # R39 opt-in QB39_GRTSETUP [1]: 0 skips the setup repair (reg2reg classes already >= 0 at GRT; the time goes into
    # chip-IO paths set by the 0.2 P budgets, e.g. h_go).  QB39_NOIO 1: the chip inputs are false-pathed during the repair only.
    # R43 opt-in QB43_NOCLONE 1 (results/r43.md, defect 7): ODB-0373 "Attempt to connect iterm to dont_touch net
    # q14s_t2317" = the resizer's gate cloning on the split14 trunk driver q14s_L* (trunk L -> R, dont_touch): r39_v
    # grt repro dies after 11-13 s with or without dont_touch on the L / R buffers, and repairs (136 s, no error) with
    # -skip_gate_cloning: OR 2.0-12381 gate cloning does not check the dont_touch output net.  Cloning off for the top.
    set _sk [expr {[qb_env QB43_NOCLONE 0] ? "-skip_gate_cloning" : ""}]
    if {[qb_env QB39_NOIO 0]} { set_false_path -from [all_inputs] }
    if {[qb_env QB39_GRTSETUP 1]} { repair_timing -setup -setup_margin 0.0 -repair_tns 100 -max_utilization [p MAX_UTIL] {*}$_sk }
    if {[qb_env QB39_NOIO 0]} { unset_path_exceptions -from [all_inputs] }
    # R43 opt-in QB43_NOIOFIX 1: that unset also drops the rst_n false path (impl/r36/top_sdc.tcl QB36_RSTFP) -> restore it
    if {[qb_env QB39_NOIO 0] && [qb_env QB43_NOIOFIX 0] && [qb_env QB36_RSTFP 1]} { set_false_path -from [get_ports rst_n] }
    qb35_stat grt_setup_repair
    # R43 opt-in QB43_HOLDFP 1 (results/r43.md, defect 2): repair_timing -hold SEGFAULTs (rsz::RepairHold::repairEndHold)
    # on endpoints that are hard-block input pins on dont_touch (block-only / abutted) nets; nothing at the top can
    # pad those (no rows, no top cell), they are block-ETM matters.  They are hold-false-pathed for the repair only.
    set _hfp {}
    if {[qb_env QB43_HOLDFP 0]} {
        foreach _i [[ord::get_db_block] getInsts] { if {[[$_i getMaster] getName] in {qb_hub qb_act2_blk qb_col_blk}} {
            foreach _it [$_i getITerms] { if {[$_it isInputSignal] && [$_it getNet] ne "NULL" && [[$_it getNet] isDoNotTouch]} { lappend _hfp [$_i getName]/[[$_it getMTerm] getName] } } } }
        if {[llength $_hfp]} { set_false_path -hold -to [get_pins $_hfp] }
        qc_log "r43: [llength $_hfp] block input pins on dont_touch nets hold-false-pathed for the repair"
    }
    if {[qb_env QB35_GRTHOLD 1] && [catch { repair_timing -hold -hold_margin [qb_env QB35_HOLD_M 0.05] -max_buffer_percent [qb_env QB_HOLD_PCT 10] \
            -max_utilization [p MAX_UTIL] } e]} { qc_log "r35: post-GRT hold repair stopped: $e" }
    if {[llength $_hfp]} { unset_path_exceptions -hold -to [get_pins $_hfp] }
    qb35_stat grt_hold_repair
    detailed_placement {*}[p DPL_ARGS]
    catch { check_placement } e; qc_log "r35 check_placement: $e"
    global_route -end_incremental
    estimate_parasitics -global_routing
    qb35_stat grt_post_repair
    # R39 opt-in QB39_WGUIDE [0]: rewrite route.guide after the repair (post_grt14.tcl wrote it before the repair: the
    # clones / buffers had no guides -> DRT-0218 in r39_w)
    if {[qb_env QB43_GRTANT 0]} { source [file normalize $::QB_R35/../r43/ant43.tcl]; q43_ant; detailed_placement {*}[p DPL_ARGS]; check_placement }
    if {[qb_env QB39_WGUIDE 0]} { write_guides $::OUT/route.guide; qc_log "r39: route.guide rewritten after the post-GRT repair" }
    qc_log "r35: post-GRT repair [expr {[clock seconds] - $_t}] s"
}
source $::QB35_R9B_ORIG/post_grt.tcl
