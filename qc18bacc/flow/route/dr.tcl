# impl/r8 run.sh dr: impl/r6c/dr.tcl (detailed route + finish in a fresh OpenROAD process from db/grt.odb +
# route.guide) with two memory knobs (defaults = r6c behaviour):
#   QB8_DR_FILL [1]  0: filler cells inserted after detailed_route instead of before (r8_a: 568 k fillers = 44 % of the
#                    1.30 M components DR loads into its region query)
#   QB8_DR_THREADS [QC_PNR_THREADS or 8]
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QB8_DR_THREADS [qc_env QC_PNR_THREADS 8]]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load grt
set_propagated_clock [all_clocks]
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
read_guides $::OUT/route.guide
qc_log "r8 dr: grt checkpoint + guides loaded ([expr {[clock seconds] - $::T0}] s)"
if {[p ANTENNA_ITER] > 0} { repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations [p ANTENNA_ITER] }
set fill {}
if {[p DCAP]} { set fill [concat $fill $::QC_PNR_DCAP] }
if {[p FILL]} { set fill [concat $fill $::QC_PNR_FILL] }
if {[llength $fill] && [qc_env QB8_DR_FILL 1]} { filler_placement $fill }
check_placement
set t [clock seconds]
detailed_route -output_drc $::OUT/rpt/drt.drc.rpt -output_maze $::OUT/drt_maze.log \
    -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
    -droute_end_iter [p DR_END_ITER] -verbose 1 {*}[p DR_ARGS]
qc_log "r8 dr: detailed_route [expr {[clock seconds] - $t}] s"
qc_save route_dr
if {[llength $fill] && ![qc_env QB8_DR_FILL 1]} { filler_placement $fill; qc_log "r8 dr: fillers after detailed_route" }
if {[p ANTENNA_CHECK]} { set t [clock seconds]; check_antennas -verbose; qc_log "r8 dr: check_antennas [expr {[clock seconds] - $t}] s" }
qc_save route
source $::env(QC_FLOW)/pnr/or/finish.tcl
qc_save finish
qc_log "r8 dr done [expr {[clock seconds] - $::T0}] s"
exit
