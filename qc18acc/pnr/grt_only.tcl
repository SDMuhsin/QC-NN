# Fallback / inspection (not part of the flow): from db/cts.odb of a qa P&R run, the route step up to the end of
# global routing (post_cts.tcl repair, global_route, post_grt.tcl repair), then checkpoint db/grt.odb and the netlist
# out/qa_top_grt.v.  Run in the P&R dir:  QC_FLOW=<repo>/flow/tsmc65 QC_PNR_OUT=$PWD openroad -exit grt_only.tcl
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 4]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load cts
source [p PRE_ROUTE_TCL]
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
global_route -guide_file $::OUT/route_grt.guide -congestion_iterations [p GR_ITER]
estimate_parasitics -global_routing
source [p POST_GRT_TCL]
qc_save grt
file mkdir $::OUT/out
write_verilog $::OUT/out/qa_top_grt.v
qc_log "grt_only done"
