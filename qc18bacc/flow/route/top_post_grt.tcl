# POST_GRT_TCL of blocks/top/top.cfg (results/r14.md, r35.md, r39.md, r43.md), GRT parasitics in memory:
#   clock      effective clock skew table (cts/top_clk_measure.tcl, rpt/clk14.txt, appended "grt"); re-balance at GRT
#              parasitics inside an incremental GRT (cts/top_balance.tcl, 2 passes), route.guide rewritten
#   drv        max slew / cap violators by class (route/top_drv_post.tcl; block-only / trunk nets are checked here)
#   classes    route/top_classes.tcl twice: propagated (balanced) clock -> rpt/classes_tt_prop.txt; ideal clock with the
#              block insertion as clock latency (column -QB11_INS, hub -QB14_HINS, act -QB14_AINS) -> classes_tt_ideal.txt
#              (the pin latencies are removed again afterwards, R43: else the block clk pins stay ideal at -INS)
#   repair     IO latency re-measured (repair/top_io_latency.tcl); inside an incremental GRT: setup repair (chip inputs
#              false-pathed for the repair only, rst_n false path restored, no gate cloning: OR 2.0-12381 ODB-0373 on the
#              dont_touch split14 trunks), QB35_GRTHOLD 1: hold repair (margin 0.05, <= 10 % buffers; OpenROAD reads the act
#              ETM without output-pin checks, R46: no repairEndHold SEGFAULT), DRV repair (repair/drv.tcl), legalisation;
#              QB43_GRTANT 1: antenna repair (repair/top_antenna.tcl); route.guide rewritten (R39: DRT-0218 otherwise)
#   then route/grt_stop.tcl (reports, db/grt.odb, exit)
foreach {_f _p} [list clk14.tcl $::QBF/cts/top_clk_measure.tcl drv_post.tcl $::QBF/route/top_drv_post.tcl] {
    catch { source $_p } _e; qc_log "r14 $_f: $_e"
}
catch { q14_report $::OUT/rpt/clk14.txt grt } _e; qc_log "r14 clk report: $_e"
# re-balance at GRT parasitics (incremental GRT)
source $::QBF/cts/top_balance.tcl
if {[catch {
    global_route -start_incremental
    q14_balance 2 global_routing grt
    global_route -end_incremental
    estimate_parasitics -global_routing
    write_guides $::OUT/route.guide
    q14_report $::OUT/rpt/clk14.txt "grt after GRT-parasitics balancing"
} _e]} { qc_log "r14 grt balance: $_e" }
catch { source $::QBF/route/top_classes.tcl } _e; qc_log "r11 classes (propagated): $_e"
catch { file rename -force $::OUT/rpt/classes_tt.txt $::OUT/rpt/classes_tt_prop.txt }
catch {
    unset_propagated_clock [all_clocks]
    set_clock_latency [expr {-$::env(QB11_INS)}] [get_pins u_top_u_core_u_arr_g_c_*__u_col/clk]
    set_clock_latency [expr {-$::env(QB14_HINS)}] [get_pins u_hub/clk]
    set_clock_latency [expr {-$::env(QB14_AINS)}] [get_pins u_act_blk/clk]
    source $::QBF/route/top_classes.tcl
    file rename -force $::OUT/rpt/classes_tt.txt $::OUT/rpt/classes_tt_ideal.txt
    set_propagated_clock [all_clocks]
    unset_clock_latency [get_pins [list u_hub/clk u_act_blk/clk]]
    unset_clock_latency [get_pins u_top_u_core_u_arr_g_c_*__u_col/clk]
    qc_log "r43: block clk pin latencies removed after the ideal-clock class report"
} _e
qc_log "r11 classes (ideal + insertion latency): $_e"
# timing repair at GRT parasitics (was impl/r35/shim/post_grt.tcl)
proc qb35_stat {tag} {
    set s [sta::worst_slack_corner [sta::find_corner tt] max]; set h [sta::worst_slack_corner [sta::find_corner tt] min]
    set ns NA; set nh NA; catch { set ns [sta::endpoint_violation_count max] }; catch { set nh [sta::endpoint_violation_count min] }
    qc_summary [format "r35 %s tt setup_wns_ns %.3f viol %s hold_wns_ns %.3f hold_viol %s %s" $tag [expr {$s*1e9}] $ns [expr {$h*1e9}] $nh [qc_util]]
}
set _t [clock seconds]
source $::QBF/repair/top_io_latency.tcl; q43_autol grt
qb35_stat grt_pre_repair
global_route -start_incremental
set_false_path -from [all_inputs]
repair_timing -setup -setup_margin 0.0 -repair_tns 100 -max_utilization [p MAX_UTIL] -skip_gate_cloning
unset_path_exceptions -from [all_inputs]
set_false_path -from [get_ports rst_n]
qb35_stat grt_setup_repair
if {$::env(QB35_GRTHOLD) && [catch { repair_timing -hold -hold_margin 0.05 -max_buffer_percent 10 \
        -max_utilization [p MAX_UTIL] } e]} { qc_log "r35: post-GRT hold repair stopped: $e" }
qb35_stat grt_hold_repair
source $::QBF/repair/drv.tcl
qb_drv postgrt
detailed_placement {*}[p DPL_ARGS]
catch { check_placement } e; qc_log "r35 check_placement: $e"
global_route -end_incremental
estimate_parasitics -global_routing
qb35_stat grt_post_repair
if {$::env(QB43_GRTANT)} { source $::QBF/repair/top_antenna.tcl; q43_ant; detailed_placement {*}[p DPL_ARGS]; check_placement }
write_guides $::OUT/route.guide; qc_log "r39: route.guide rewritten after the post-GRT repair"
qc_log "r35: post-GRT repair [expr {[clock seconds] - $_t}] s"
source $::QBF/route/grt_stop.tcl
