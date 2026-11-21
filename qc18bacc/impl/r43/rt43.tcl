# R43 (results/r43.md): reproduce / root-cause the top repair crashes on a routed-flow checkpoint (read-only: no db
# written, no route.guide).  In a run dir via impl/r29/or29.sh <tag> rt43.tcl <log>, with that run's env.
#   R43_DB [grt]   checkpoint;  R43_GRT [1] re-run global_route (GRT parasitics) as the flow
#   R43_DO  list of {setup hold}: repair_timing per item, each in catch with ::errorInfo printed
#   R43_DTREL [0]  1: clear dont_touch on the split14 trunks (q14s_t*) before the repair (ODB-0373 test)
#   R43_DTLIST [0] 1: print every dont_touch net / inst and its terminals' masters
#   R43_SKIPCLONE [0] 1: repair_timing -setup -skip_gate_cloning (move-identification test)
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 16]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R43_DB grt]
if {[qc_env R43_GRT 1]} {
    set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
    set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
    foreach {l a} [qc_env QB15_GADJ_L "M2-M3 0.6"] { set_global_routing_layer_adjustment $l $a }
    global_route -congestion_iterations [p GR_ITER] -allow_congestion
    estimate_parasitics -global_routing
} else { estimate_parasitics -placement }
# R43_UNLAT 1: remove the block clk pin latencies that db/grt.sdc carries (post_grt14 ideal-class report, QB43_LATFIX)
if {[qc_env R43_UNLAT 0]} { unset_clock_latency [get_pins [list u_hub/clk u_act_blk/clk]]; unset_clock_latency [get_pins u_top_u_core_u_arr_g_c_*__u_col/clk]; puts "R43_UNLAT done" }
# R43_HFP 1: hold false paths to the hard-block input pins (crash bisection: block-only dont_touch nets)
if {[qc_env R43_HFP 0]} {
    set _bp {}; foreach _i [[ord::get_db_block] getInsts] { if {[[$_i getMaster] getName] in {qb_hub qb_act2_blk qb_col_blk}} {
        foreach _t [$_i getITerms] { if {[$_t isInputSignal] && [$_t getNet] ne "NULL" && ([qc_env R43_HFP 0] != 2 || [[$_t getNet] isDoNotTouch])} { lappend _bp [$_i getName]/[[$_t getMTerm] getName] } } } }
    set_false_path -hold -to [get_pins $_bp]; puts "R43_HFP [llength $_bp] block input pins"
}
set blk [ord::get_db_block]; set ndt 0; set nidt 0
foreach n [$blk getNets] { if {[$n isDoNotTouch]} { incr ndt
    if {[qc_env R43_DTLIST 0]} { puts "R43_DTNET [$n getName] [lmap t [$n getITerms] {[[[$t getInst] getMaster] getName]/[[$t getMTerm] getName]}]" } } }
foreach i [$blk getInsts] { if {[$i isDoNotTouch]} { incr nidt } }
puts "R43_DT nets $ndt insts $nidt"
if {[qc_env R43_DTREL 0]} {
    set l {}; foreach n [$blk getNets] { if {[$n isDoNotTouch] && [string match q14s_t* [$n getName]]} { lappend l [$n getName] } }
    unset_dont_touch [get_nets $l]; puts "R43_DTREL [llength $l] trunks released"
}
set _sk [expr {[qc_env R43_SKIPCLONE 0] ? "-skip_gate_cloning" : ""}]
foreach d [qc_env R43_DO {setup hold}] {
    set t [clock seconds]
    puts "R43_START $d tt setup [sta::worst_slack_corner [sta::find_corner tt] max] hold [sta::worst_slack_corner [sta::find_corner tt] min] hold_viol [sta::endpoint_violation_count min]"
    if {$d eq "setup"} {
        set rc [catch { repair_timing -setup -setup_margin 0.0 -repair_tns 100 -max_utilization [p MAX_UTIL] {*}$_sk } e]
    } else {
        set rc [catch { repair_timing -hold -hold_margin 0.05 -max_buffer_percent [qc_env QB_HOLD_PCT 10] -max_utilization [p MAX_UTIL] } e]
    }
    puts "R43_END $d rc $rc [expr {[clock seconds] - $t}] s: $e"
    if {$rc} { puts "R43_ERRINFO $::errorInfo" }
    puts "R43_AFTER $d tt setup [sta::worst_slack_corner [sta::find_corner tt] max] hold [sta::worst_slack_corner [sta::find_corner tt] min] hold_viol [sta::endpoint_violation_count min] insts [llength [$blk getInsts]]"
}
