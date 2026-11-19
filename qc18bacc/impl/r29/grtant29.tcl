# R29: antenna estimate at global-route time vs routed.  In a run dir (env QC_PNR_OUT, QC_FLOW as impl/r28/ant28.sh):
#   R29_DB [route_dr]: db to load.  R29_GRT 1: re-run global_route (flow layers + gadj M2-M9 0.25, M5-M9 0.10) first.
#   R29_NETS: nets for check_antennas -verbose -net.  Writes rpt/r29_ant_<tag>.rpt (full check) when R29_FULL 1.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set_thread_count 16
read_db $::OUT/db/[qc_env R29_DB route_dr].odb
set tag [qc_env R29_TAG x]
if {[qc_env R29_GRT 0]} {
    set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
    set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER 0.25
    set_global_routing_layer_adjustment M5-M9 0.10
    set t [clock seconds]
    global_route -congestion_iterations 10 -allow_congestion
    puts "R29 grt [expr {[clock seconds]-$t}] s"
}
foreach n [qc_env R29_NETS ""] { puts "R29 NET $n"; check_antennas -verbose -net $n }
if {[qc_env R29_FULL 0]} {
    set t [clock seconds]
    check_antennas -report_file $::OUT/rpt/r29_ant_$tag.rpt
    puts "R29 full check [expr {[clock seconds]-$t}] s"
}
exit
