# R34 POST_GRT_TCL (impl/r34/preset.env; results/r34.md).  Opt-in QB34_GRTREP 1 (R33 defect 1): timing repair at
# global-route parasitics, which the flow never did (reg2reg clean at placement parasitics, lost at GRT):
#   global_route -start_incremental; IO paths out of the repair (QB34_GRT_IOFP [1]: max IO delays relaxed, restored
#   after); repair_timing -setup (repair_tns QB34_GRT_TNS [100]); optional hold repair (QB34_GRT_HOLD [0], all paths);
#   detailed_placement; global_route -end_incremental; GRT parasitics.
# Then impl/r21/post_grt.tcl (antenna repair, guides, reports, db/grt.odb, exit).
proc qb34_tstat {tag} {
    set ws [expr {[sta::worst_slack_cmd max] * 1e9}]; set n [sta::endpoint_violation_count max]
    set nh 0; catch { set nh [sta::endpoint_violation_count min] }
    set a 0.0; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    foreach i [[ord::get_db_block] getInsts] { set m [$i getMaster]; if {![$m isBlock]} { set a [expr {$a + [$m getWidth] * [$m getHeight]}] } }
    qc_log [format "r34: %s wns %.3f viol %d hold_viol %d std_um2 %.0f" $tag $ws $n $nh [expr {$a / $u / $u}]]
}
# v3 notes (results/r34.md sec. 2): no filtered (-from / -to) searches here (v1 SIGSEGV in a threaded arrival search),
# no set_thread_count toggling (v2: back at 16 threads, the next report_checks spun forever in DispatchQueue::finishTasks)
# and no path exceptions: the IO paths are taken out of the repair by relaxing only their max delays (inputs and outputs
# -max -2 P), then the IO budget is re-applied exactly (impl/r5a budget qb5_io_apply P L, L = QB_IO_LAT).
if {[qb_env QB34_GRTREP 0]} {
    set _t [clock seconds]
    qb34_tstat grt_pre_repair
    global_route -start_incremental
    set _iofp [qb_env QB34_GRT_IOFP 1]
    set _per [get_property [get_clocks qb_clk] period]
    if {$_iofp} {
        set _ck {}; foreach c [all_clocks] { foreach sp [get_property $c sources] { lappend _ck [get_full_name $sp] } }
        set _in {}; foreach pt [all_inputs] { if {[get_full_name $pt] ni $_ck && [get_full_name $pt] ne "rst_n"} { lappend _in $pt } }
        set _out [all_outputs]
        set_input_delay -max [expr {-2.0 * $_per}] -clock qb_clk $_in
        set_output_delay -max [expr {-2.0 * $_per}] -clock qb_clk $_out
        qb34_tstat grt_io_relaxed
    }
    repair_timing -setup -setup_margin 0.0 -repair_tns [qb_env QB34_GRT_TNS 100] -max_utilization [p MAX_UTIL]
    qc_log "r34: post-GRT repair_timing -setup [expr {[clock seconds] - $_t}] s"
    if {$_iofp} {
        if {[info commands qb5_io_apply] eq ""} { source $::env(QB_IO_BUDGET) }
        qb5_io_apply $_per [qb_env QB_IO_LAT 0.85]
        qc_log "r34: IO budget re-applied (P $_per L [qb_env QB_IO_LAT 0.85])"
    }
    if {[qb_env QB34_GRT_HOLD 0]} {
        if {[catch { repair_timing -hold -hold_margin [p HOLD_MARGIN] -max_buffer_percent [qb_env QB_HOLD_PCT 10] \
                -max_utilization [p MAX_UTIL] } e]} { qc_log "r34: post-GRT repair_timing -hold stopped: $e" }
    }
    detailed_placement {*}[p DPL_ARGS]
    if {[catch {check_placement} e]} { qc_log "r34: check_placement after the post-GRT repair: $e" }
    global_route -end_incremental
    estimate_parasitics -global_routing
    qb34_tstat grt_post_repair
    qc_log "r34: post-GRT repair total [expr {[clock seconds] - $_t}] s"
}
qb34_ckcount grt
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r21/post_grt.tcl]
