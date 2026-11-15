# impl/r5b: global-route probe of a chip checkpoint (QB_FROM, default place) in parallel with the flow (results/r5b.md):
# same layers / adjustment / iterations as the flow's route step, congestion report rpt/gr_probe_<step>.rpt, no save.
#   cd <run> && QC_FLOW=<repo>/flow/tsmc65 QC_PNR_OUT=$PWD QB_FROM=place openroad -exit grt_probe.tcl
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 8]
set ::STEPS {init floorplan pdn place cts route finish}
set s [qc_env QB_FROM place]
qc_load $s
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
global_route -congestion_iterations [p GR_ITER] -congestion_report_file $::OUT/rpt/gr_probe_$s.rpt
qc_log "grt_probe $s done [expr {[clock seconds] - $::T0}] s"
exit
