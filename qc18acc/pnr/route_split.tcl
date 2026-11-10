# The flow's route step (flow/tsmc65/pnr/or/route.tcl) split into two OpenROAD processes, for designs whose detailed
# route does not fit in RAM next to the timing data (v4: 2x the v3 nets; v3's single route process peaked at 25.2 GB
# of the hosts' 30 GB, 21 GB of it TritonRoute's own after pin access / guide setup).
#   QA_PART=grt: load db/cts.odb (liberty, SDC, propagated clock), PRE_ROUTE_TCL, global route, POST_GRT_TCL (setup /
#                hold repair + incremental global route), check_placement; write the final guides (route_grt.guide)
#                and db/route_grt.odb / .sdc.  No fillers / decaps yet (v3: 815 k instances for 422 k nets; the
#                filler / decap cells carry only PG pins, so they can be inserted after detailed route).
#   QA_PART=drt: fresh process without liberty / STA: read db/route_grt.odb + route_grt.guide, detailed route
#                (P(DR_END_ITER), P(DR_ARGS)), fillers / decaps, write db/route_dr.odb and db/route.odb (+ the GRT SDC), so that
#                QC_PNR_FROM=finish run_pnr.sh continues with the flow's finish step and the SPEF / STA post steps.
#   cd <run dir>; QC_FLOW=<repo>/flow/tsmc65 QC_PNR_OUT=<run dir> QC_BUILD=... QA_PART=grt|drt openroad -exit route_split.tcl
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 14]
set ::STEPS {init floorplan pdn place cts route finish}
set part [qc_env QA_PART grt]
if {$part eq "grt"} {
    qc_load cts
    qc_log "route_split grt"
    if {[p PRE_ROUTE_TCL] ne ""} { source [p PRE_ROUTE_TCL] }
    set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
    set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
    global_route -guide_file $::OUT/route.guide -congestion_iterations [p GR_ITER] \
        -congestion_report_file $::OUT/rpt/gr_congestion.rpt
    estimate_parasitics -global_routing
    qc_summary "groute [join [qc_timing_lines groute] { | }]"
    if {[p POST_GRT_TCL] ne ""} { source [p POST_GRT_TCL] }
    check_placement
    write_guides $::OUT/route_grt.guide
    qc_save route_grt
} elseif {$part eq "drt"} {
    read_db $::OUT/db/route_grt.odb
    read_guides $::OUT/route_grt.guide
    qc_log "route_split drt: guides read ([expr {[clock seconds] - $::T0}] s)"
    detailed_route -output_drc $::OUT/rpt/drt.drc.rpt -output_maze $::OUT/drt_maze.log \
        -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
        -droute_end_iter [p DR_END_ITER] -verbose 1 {*}[p DR_ARGS]
    set fill {}
    if {[p DCAP]} { set fill [concat $fill $::QC_PNR_DCAP] }
    if {[p FILL]} { set fill [concat $fill $::QC_PNR_FILL] }
    if {[llength $fill]} { filler_placement $fill }
    check_placement
    foreach s {route_dr route} {
        write_db $::OUT/db/$s.odb
        file copy -force $::OUT/db/route_grt.sdc $::OUT/db/$s.sdc
    }
    qc_log "route_split drt done ([expr {[clock seconds] - $::T0}] s)"
} else {
    error "QA_PART must be grt or drt"
}
exit
