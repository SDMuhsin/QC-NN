# R43 post-GRT hold + antenna step for the chip top (results/r43.md, defect 2 / 5), in a run dir via
# impl/r29/or29.sh <tag> hold43.tcl <log> with the run env, after tpnr wrote db/grt.odb (run with QB35_GRTHOLD 0,
# QB43_GRTANT 0).  The in-flow hold repair (inside the shim's incremental GRT, after the setup repair) segfaulted in
# rsz::RepairHold::repairEndHold on r43_a even with QB43_HOLDFP; here it runs in its own process:
#   qc_load grt -> global_route (flow settings) -> parasitics R43_HPAR [global_routing] -> hold false paths to the block
#   inputs on dont_touch nets (QB43_HOLDFP rule) -> repair_timing -hold (margin QB35_HOLD_M [0.05]) -> DPL + keep-out
#   check -> incremental GRT of the new buffers -> antenna repair (impl/r43/ant43.tcl) -> route.guide -> db/grt.odb.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 16]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load grt
proc qb_env {n d} { return [expr {[info exists ::env($n)] ? $::env($n) : $d}] }
# keep-out check (rows were removed at place; re-register the hub halo rectangle for the check)
source $::env(QC_FLOW)/../../qc18bacc/impl/r43/keepout43.tcl
set b [ord::get_db_block]; set u [$b getDefUnits]
if {[llength [qb_env QB39_HUBHALO ""]] == 2} { lassign [qb_env QB39_HUBHALO ""] _h _w
    foreach i [$b getInsts] { if {[[$i getMaster] getName] eq "qb_hub"} { set bb [$i getBBox]
        lappend ::Q43_KO [list [$bb xMin] [$bb yMax] [expr {[$bb xMin] + int($_w * $u)}] [expr {[$bb yMax] + int($_h * $u)}]] } } }
proc h43 {tag} {
    set h [sta::worst_slack_corner [sta::find_corner tt] min]; set s [sta::worst_slack_corner [sta::find_corner tt] max]
    qc_summary [format "r43 hold43 %s tt setup_wns_ns %.3f setup_viol %d hold_wns_ns %.3f hold_viol %d %s" $tag [expr {$s*1e9}] \
        [sta::endpoint_violation_count max] [expr {$h*1e9}] [sta::endpoint_violation_count min] [qc_util]]
}
# the chip reset is asynchronous and false-pathed (impl/r36/top_sdc.tcl QB36_RSTFP); the shim's QB39_NOIO
# "unset_path_exceptions -from [all_inputs]" also removed that exception (r43_a: rst_n removal -1.45 after the setup repair)
if {[qb_env QB36_RSTFP 1]} { set_false_path -from [get_ports rst_n] }
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
foreach {l a} [qc_env QB15_GADJ_L "M2-M3 0.6"] { set_global_routing_layer_adjustment $l $a }
# R43_HGRT0 [1]: global route before the repair (0 = none: hold repair on placement parasitics with no GRT data at all)
if {[qc_env R43_HGRT0 1]} { global_route -congestion_iterations [p GR_ITER] -allow_congestion }
estimate_parasitics -[qc_env R43_HPAR global_routing]
h43 pre
set _hfp {}
# R43_HFPIN [1]: 0 = no hold false paths to the dont_touch block inputs (R46: test whether the QB43_HOLDFP rule is needed)
if {[qc_env R43_HFPIN 1]} {
foreach _i [$b getInsts] { if {[[$_i getMaster] getName] in {qb_hub qb_act2_blk qb_col_blk}} {
    foreach _t [$_i getITerms] { if {[$_t isInputSignal] && [$_t getNet] ne "NULL" && [[$_t getNet] isDoNotTouch]} { lappend _hfp [$_i getName]/[[$_t getMTerm] getName] } } } }
}
if {[llength $_hfp]} { set_false_path -hold -to [get_pins $_hfp] }
qc_log "r43 hold43: [llength $_hfp] block inputs on dont_touch nets hold-false-pathed"
qc_to $::OUT/rpt/r43_hold_pre.rpt { report_checks -path_delay min -group_count 2000 -endpoint_count 1 -format end }
# R43_HINC [1]: repair inside global_route -start_incremental (new buffers routed incrementally); 0: no GRT session
# during the repair and a full global route afterwards (r43_a: repairEndHold SEGFAULT inside the incremental session
# with placement parasitics, where the same repair on r39_v without a session ran clean)
if {[qc_env R43_HINC 1]} { global_route -start_incremental }
set t [clock seconds]
# R43_HOLD [1]: 0 = no hold repair (antenna + guides only)
if {[qc_env R43_HOLD 1]} {
repair_timing -hold -hold_margin [qc_env QB35_HOLD_M 0.05] -max_buffer_percent [qc_env QB_HOLD_PCT 10] -max_utilization [p MAX_UTIL]
}
qc_log "r43 hold43: repair_timing -hold [expr {[clock seconds] - $t}] s"
if {[llength $_hfp]} { unset_path_exceptions -hold -to [get_pins $_hfp] }
detailed_placement {*}[p DPL_ARGS]
check_placement
if {[qc_env R43_HINC 1]} { global_route -end_incremental -allow_congestion } else { global_route -congestion_iterations [p GR_ITER] -allow_congestion }
estimate_parasitics -global_routing
h43 post_hold
if {[qb_env QB43_GRTANT 1]} { source $::env(QC_FLOW)/../../qc18bacc/impl/r43/ant43.tcl; q43_ant; detailed_placement {*}[p DPL_ARGS]; check_placement }
estimate_parasitics -global_routing
h43 post_ant
write_guides $::OUT/route.guide
qc_save grt
qc_log "r43 hold43 done"
