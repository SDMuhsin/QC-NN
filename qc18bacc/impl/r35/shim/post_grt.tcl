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
    qb35_stat grt_pre_repair
    global_route -start_incremental
    if {[qb_env QB35_GRTDRV 1]} {
        if {[catch { repair_design -max_utilization [p MAX_UTIL] } e]} { qc_log "r35: post-GRT repair_design: $e" }
        qb35_stat grt_drv_repair
    }
    # R39 opt-in QB39_GRTSETUP [1]: 0 skips the setup repair (reg2reg classes already >= 0 at GRT; the time goes into
    # chip-IO paths set by the 0.2 P budgets, e.g. h_go).  QB39_NOIO 1: the chip inputs are false-pathed during the repair only.
    if {[qb_env QB39_NOIO 0]} { set_false_path -from [all_inputs] }
    if {[qb_env QB39_GRTSETUP 1]} { repair_timing -setup -setup_margin 0.0 -repair_tns 100 -max_utilization [p MAX_UTIL] }
    if {[qb_env QB39_NOIO 0]} { unset_path_exceptions -from [all_inputs] }
    qb35_stat grt_setup_repair
    if {[qb_env QB35_GRTHOLD 1] && [catch { repair_timing -hold -hold_margin [qb_env QB35_HOLD_M 0.05] -max_buffer_percent [qb_env QB_HOLD_PCT 10] \
            -max_utilization [p MAX_UTIL] } e]} { qc_log "r35: post-GRT hold repair stopped: $e" }
    detailed_placement {*}[p DPL_ARGS]
    catch { check_placement } e; qc_log "r35 check_placement: $e"
    global_route -end_incremental
    estimate_parasitics -global_routing
    qb35_stat grt_post_repair
    # R39 opt-in QB39_WGUIDE [0]: rewrite route.guide after the repair (post_grt14.tcl wrote it before the repair: the
    # clones / buffers had no guides -> DRT-0218 in r39_w)
    if {[qb_env QB39_WGUIDE 0]} { write_guides $::OUT/route.guide; qc_log "r39: route.guide rewritten after the post-GRT repair" }
    qc_log "r35: post-GRT repair [expr {[clock seconds] - $_t}] s"
}
source $::QB35_R9B_ORIG/post_grt.tcl
