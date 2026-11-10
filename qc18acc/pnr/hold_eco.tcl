# Post-route hold ECO of a QC18-ACC P&R run (not part of the flow; results/pnr_v3.md "hold ECO").  Run in a COPY of
# a routed run dir (db/finish.odb, out/<top>_<corner>.spef):
#   QC_FLOW=... QC_PNR_OUT=<copy> [QA_ECO_DR=0|1] [QA_ECO_MARGIN=0.05] [QA_ECO_RE=<regexp of endpoint instances>]
#   openroad -exit hold_eco.tcl
# 1. load finish.odb, the def2spef SPEF of every corner (routed parasitics), report the hold violators;
# 2. remove the fillers, put a hold-only clock uncertainty of QA_ECO_MARGIN ns (default 0.05 = the flow's
#    HOLD_MARGIN) on the endpoints matching QA_ECO_RE (default: the weight-macro instances u_wmem_*), and run
#    repair_timing -hold (OpenROAD resizer: delay / hold buffers in front of the violating endpoints, timed with the
#    routed parasitics of the existing nets; the new nets get placement estimates);
# 3. legalise (detailed_placement), fillers back, incremental global route of the changed nets;
# 4. QA_ECO_DR=1: detailed route again (TritonRoute of this build re-routes the whole design) with P(DR_END_ITER),
#    checkpoint db/route_dr.odb, then the finish step (out/: def, v, conn) - def2spef / PrimeTime as for a flow run.
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 14]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load finish
set top [p TOP]
foreach c $::QC_CORNERS { read_spef -corner $c $::OUT/out/${top}_$c.spef }
proc eco_hold {tag} {
    foreach l [qc_timing_lines eco_$tag] { qc_log "ECO $l" }
    qc_to $::OUT/rpt/eco_$tag.min.rpt { report_checks -path_delay min -group_count 200 -endpoint_count 1 -format end -digits 3 }
    foreach c {tt ss} {
        qc_to $::OUT/rpt/eco_$tag.$c.min.rpt { report_checks -corner $c -path_delay min -digits 3 -fields {slew cap} }
    }
}
eco_hold pre
set re [qc_env QA_ECO_RE {^u_wmem_[eo]/}]
set m [qc_env QA_ECO_MARGIN 0.05]
set pins {}
foreach i [[ord::get_db_block] getInsts] {
    if {[[$i getMaster] isBlock] && [regexp $re [$i getName]]} { lappend pins [get_pins [$i getName]/CLK] }
}
set_clock_uncertainty -hold [expr {[qc_env QC_UNC_HOLD 0.05] + $m}] $pins
qc_log "ECO: +$m ns hold uncertainty on [llength $pins] macro CLK pins matching $re"
remove_fillers
global_route -start_incremental
repair_timing -hold -hold_margin [p HOLD_MARGIN] -max_utilization [p MAX_UTIL]
detailed_placement -max_displacement {300 300}
check_placement
set fill {}
if {[p DCAP]} { set fill [concat $fill $::QC_PNR_DCAP] }
if {[p FILL]} { set fill [concat $fill $::QC_PNR_FILL] }
if {[llength $fill]} { filler_placement $fill }
global_route -end_incremental -congestion_report_file $::OUT/rpt/gr_congestion_eco.rpt
eco_hold post_repair
qc_save eco_grt
if {[qc_env QA_ECO_DR 0]} {
    detailed_route -output_drc $::OUT/rpt/drt.drc.rpt -output_maze $::OUT/drt_maze.log \
        -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
        -droute_end_iter [p DR_END_ITER] -verbose 1 {*}[p DR_ARGS]
    qc_save route_dr
    source $::env(QC_FLOW)/pnr/or/finish.tcl
    qc_save finish
}
qc_log "hold_eco done ([expr {[clock seconds] - $::T0}] s)"
