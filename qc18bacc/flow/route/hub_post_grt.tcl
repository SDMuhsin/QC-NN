# POST_GRT_TCL of blocks/hub/hub.cfg (results/r21.md, r33.md, r34.md); one file for impl/r34/post_grt -> r21/post_grt:
#   1. (R33 defect 1) timing + DRV repair at global-route parasitics, which the flow never did (reg2reg clean at placement
#      parasitics, lost at GRT): global_route -start_incremental; IO paths out of the repair (max IO delays relaxed,
#      restored after); repair_timing -setup (repair_tns 100); hold repair (all paths, margin P(HOLD_MARGIN), at most
#      10 % new buffers); DRV repair (repair/drv.tcl); detailed_placement; global_route -end_incremental; GRT parasitics
#   2. antenna repair at global-route time (3 iterations, diode $::QC_PNR_DIODE), guides rewritten after it
#   3. route/grt_stop.tcl: GRT timing reports, checkpoint db/grt.odb, exit (DR in its own process: route/dr.sh)
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
# -max -2 P), then the IO budget is re-applied exactly (impl/r5a budget qb5_io_apply P L, L = QB_IO_LAT measured after CTS, cts/clk_lat.tcl).
set _t [clock seconds]
qb34_tstat grt_pre_repair
global_route -start_incremental
set _per [get_property [get_clocks qb_clk] period]
set _ck {}; foreach c [all_clocks] { foreach sp [get_property $c sources] { lappend _ck [get_full_name $sp] } }
set _in {}; foreach pt [all_inputs] { if {[get_full_name $pt] ni $_ck && [get_full_name $pt] ne "rst_n"} { lappend _in $pt } }
set _out [all_outputs]
set_input_delay -max [expr {-2.0 * $_per}] -clock qb_clk $_in
set_output_delay -max [expr {-2.0 * $_per}] -clock qb_clk $_out
qb34_tstat grt_io_relaxed
repair_timing -setup -setup_margin 0.0 -repair_tns 100 -max_utilization [p MAX_UTIL]
qc_log "r34: post-GRT repair_timing -setup [expr {[clock seconds] - $_t}] s"
if {[info commands qb5_io_apply] eq ""} { source $::env(QB_IO_BUDGET) }
qb5_io_apply $_per $::env(QB_IO_LAT)
qc_log "r34: IO budget re-applied (P $_per L $::env(QB_IO_LAT), measured after CTS)"
if {[catch { repair_timing -hold -hold_margin [p HOLD_MARGIN] -max_buffer_percent 10 \
        -max_utilization [p MAX_UTIL] } e]} { qc_log "r34: post-GRT repair_timing -hold stopped: $e" }
source $::QBF/repair/drv.tcl
qb_drv postgrt
detailed_placement {*}[p DPL_ARGS]
if {[catch {check_placement} e]} { qc_log "r34: check_placement after the post-GRT repair: $e" }
global_route -end_incremental
estimate_parasitics -global_routing
qb34_tstat grt_post_repair
qc_log "r34: post-GRT repair total [expr {[clock seconds] - $_t}] s"
qb34_ckcount grt
set t [clock seconds]
repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations 3
write_guides $::OUT/route.guide
qc_log "r21: repair_antennas [expr {[clock seconds] - $t}] s, guides rewritten"
qc_to $::OUT/rpt/grt_drv.rpt { report_check_types -max_slew -max_capacitance -max_fanout }
source $::QBF/route/grt_stop.tcl
