# route: global route, hook POST_GRT_TCL (e.g. timing repair at global-route parasitics), antenna repair,
# fillers / decaps, detailed route, antenna check.
if {[p PRE_ROUTE_TCL] ne ""} { source [p PRE_ROUTE_TCL] }
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
global_route -guide_file $::OUT/route.guide -congestion_iterations [p GR_ITER] \
    -congestion_report_file $::OUT/rpt/gr_congestion.rpt
estimate_parasitics -global_routing
qc_summary "groute [join [qc_timing_lines groute] { | }]"
if {[p POST_GRT_TCL] ne ""} { source [p POST_GRT_TCL] }
if {[p ANTENNA_ITER] > 0} { repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations [p ANTENNA_ITER] }
set fill {}
if {[p DCAP]} { set fill [concat $fill $::QC_PNR_DCAP] }
if {[p FILL]} { set fill [concat $fill $::QC_PNR_FILL] }
if {[llength $fill]} { filler_placement $fill }
check_placement
detailed_route -output_drc $::OUT/rpt/drt.drc.rpt -output_maze $::OUT/drt_maze.log \
    -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
    -droute_end_iter [p DR_END_ITER] -verbose 1 {*}[p DR_ARGS]
check_antennas -verbose
if {[p POST_ROUTE_TCL] ne ""} { source [p POST_ROUTE_TCL] }
