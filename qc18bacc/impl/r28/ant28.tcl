# R28 (results/r28.md): post-DR antenna repair of a routed hub (opt-in; ORFS-style: repair_antennas on the detailed
# routes inserts diodes, then detailed_route on the routed db connects them and repairs, then check_antennas).
#   on tau, in the run dir (impl/r28/ant28.sh <tag>): input db/route_dr.odb (after eco28), guides route.guide.
#   QB28_ANT_ITER [1] repair_antennas iterations, QB28_ANT_DR [8] DRT iterations; writes rpt/ant28_{pre,post}.rpt,
#   rpt/ant28_drt.rpt; when DRT ends with 0 markers and check_antennas 0: route_dr / route / finish (as impl/r8/dr.tcl).
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QB8_DR_THREADS [qc_env QC_PNR_THREADS 8]]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load route_dr
set_propagated_clock [all_clocks]
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
proc nant {f} { set g [open $f]; set t [read $g]; close $g; return [regexp -all -line {^Net:} $t] }
check_antennas -report_file $::OUT/rpt/ant28_pre.rpt
puts "R28_ANT pre nets [nant $::OUT/rpt/ant28_pre.rpt] ([expr {[clock seconds] - $::T0}] s)"
read_guides $::OUT/route.guide
set n0 [llength [[ord::get_db_block] getInsts]]
if {[qc_env QB28_ANT_ITER 1] > 0} { repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations [qc_env QB28_ANT_ITER 1] }
puts "R28_ANT diodes inserted [expr {[llength [[ord::get_db_block] getInsts]] - $n0}] ([expr {[clock seconds] - $::T0}] s)"
set t [clock seconds]
detailed_route -output_drc $::OUT/rpt/ant28_drt.rpt -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
    -droute_end_iter [qc_env QB28_ANT_DR 8] -verbose 1
puts "R28_ANT detailed_route [expr {[clock seconds] - $t}] s"
set g [open $::OUT/rpt/ant28_drt.rpt]; set ndr [regexp -all {violation type} [read $g]]; close $g
check_antennas -report_file $::OUT/rpt/ant28_post.rpt
set na [nant $::OUT/rpt/ant28_post.rpt]
puts "R28_ANT post: DRT markers $ndr, antenna nets $na"
write_db $::OUT/db/route_ant28.odb
if {$ndr == 0 && $na == 0 && [qc_env QB28_ANT_SAVE 1]} {
    qc_save route_dr
    set fill [concat [expr {[p DCAP] ? $::QC_PNR_DCAP : {}}] [expr {[p FILL] ? $::QC_PNR_FILL : {}}]]
    if {[llength $fill] && ![qc_env QB8_DR_FILL 1]} { filler_placement $fill }
    qc_save route
    source $::env(QC_FLOW)/pnr/or/finish.tcl
    qc_save finish
    puts "R28_ANT saved route_dr / route / finish"
}
qc_log "r28 ant done [expr {[clock seconds] - $::T0}] s"
exit
