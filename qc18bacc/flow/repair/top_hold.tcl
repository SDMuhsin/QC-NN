# Post-GRT hold + antenna step of the chip top (results/r43.md defect 2 / 5, r46.md) in a fresh OpenROAD process after
# blocks/top/run.sh pnr wrote db/grt.odb (blocks/top/run.sh hold: common/or.sh <tag> repair/top_hold.tcl <log>):
#   qc_load grt -> global_route (flow settings; R43_HGRT0 [1]) -> parasitics R43_HPAR [global_routing] ->
#   repair_timing -hold (margin 0.05, <= 10 % buffers; R43_HOLD [1]) + DRV repair (repair/drv.tcl) ->
#   DPL + keep-out check -> GRT of the new buffers (incremental session R43_HINC [1], else a full global route) ->
#   antenna repair (repair/top_antenna.tcl) -> route.guide -> db/grt.odb.
# (r43_a chain2 ran the defaults; R46's clean measured run: R43_HPAR placement, R43_HGRT0 0, R43_HINC 0.)
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 16]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load grt
# keep-out check (rows were removed at place; re-register the hub halo rectangle for the check)
source $::QBF/place/keepout.tcl
set b [ord::get_db_block]; set u [$b getDefUnits]
lassign $::QB_HUBHALO _h _w
foreach i [$b getInsts] { if {[[$i getMaster] getName] eq "qb_hub"} { set bb [$i getBBox]
    lappend ::Q43_KO [list [$bb xMin] [$bb yMax] [expr {[$bb xMin] + int($_w * $u)}] [expr {[$bb yMax] + int($_h * $u)}]] } }
proc h43 {tag} {
    set h [sta::worst_slack_corner [sta::find_corner tt] min]; set s [sta::worst_slack_corner [sta::find_corner tt] max]
    qc_summary [format "r43 hold43 %s tt setup_wns_ns %.3f setup_viol %d hold_wns_ns %.3f hold_viol %d %s" $tag [expr {$s*1e9}] \
        [sta::endpoint_violation_count max] [expr {$h*1e9}] [sta::endpoint_violation_count min] [qc_util]]
}
# the chip reset is asynchronous and false-pathed (blocks/top/top_sdc.tcl); before the R43 fix the post-GRT repair's
# "unset_path_exceptions -from [all_inputs]" also removed that exception (r43_a: rst_n removal -1.45 after the setup repair)
set_false_path -from [get_ports rst_n]
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
# (the per-layer QB15_GADJ_L pairs follow from the route/gadj_layers.tcl wrapper that top.cfg installs; R47: this script
# applied them a second time)
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
# R43_HGRT0 [1]: global route before the repair (0 = none: hold repair on placement parasitics with no GRT data at all)
if {[qc_env R43_HGRT0 1]} { global_route -congestion_iterations [p GR_ITER] -allow_congestion }
estimate_parasitics -[qc_env R43_HPAR global_routing]
h43 pre
qc_to $::OUT/rpt/r43_hold_pre.rpt { report_checks -path_delay min -group_count 2000 -endpoint_count 1 -format end }
# R43_HINC [1]: repair inside global_route -start_incremental (new buffers routed incrementally); 0: no GRT session
# during the repair and a full global route afterwards (r43_a: repairEndHold SEGFAULT inside the incremental session
# with placement parasitics, where the same repair on r39_v without a session ran clean)
if {[qc_env R43_HINC 1]} { global_route -start_incremental }
set t [clock seconds]
# R43_HOLD [1]: 0 = no hold repair (antenna + guides only)
if {[qc_env R43_HOLD 1]} {
repair_timing -hold -hold_margin 0.05 -max_buffer_percent 10 -max_utilization [p MAX_UTIL]
}
qc_log "r43 hold43: repair_timing -hold [expr {[clock seconds] - $t}] s"
source $::QBF/repair/drv.tcl
qb_drv hold
detailed_placement {*}[p DPL_ARGS]
check_placement
if {[qc_env R43_HINC 1]} { global_route -end_incremental -allow_congestion } else { global_route -congestion_iterations [p GR_ITER] -allow_congestion }
estimate_parasitics -global_routing
h43 post_hold
source $::QBF/repair/top_antenna.tcl; q43_ant; detailed_placement {*}[p DPL_ARGS]; check_placement
estimate_parasitics -global_routing
h43 post_ant
write_guides $::OUT/route.guide
qc_save grt
qc_log "r43 hold43 done"
