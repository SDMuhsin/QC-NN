# R29: antenna-checker experiment on a run's grt db: global_route (flow settings), then for each net of R29_NETS
# the iterms (master / pin / location) and check_antennas -verbose -net; optional R29_REPAIR 1: repair_antennas after.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R29_DB grt]
set_thread_count 16
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
foreach {l a} [qc_env QB15_GADJ_L ""] { set_global_routing_layer_adjustment $l $a }
global_route -congestion_iterations [p GR_ITER] -allow_congestion
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]
proc show {} {
  foreach n [qc_env R29_NETS ""] {
    set net [$::blk findNet $n]
    puts "R29X NET $n"
    foreach it [$net getITerms] { set b [$it getBBox]
        puts [format "R29X   %s %s %s %.1f %.1f" [[$it getInst] getName] [[[$it getInst] getMaster] getName] [[$it getMTerm] getName] [expr {[$b xMin]/$::u}] [expr {[$b yMin]/$::u}]] }
    check_antennas -verbose -net $n
  }
}
if {[catch show e]} { puts "R29X show error: $e" }
if {[qc_env R29_REPAIR 0]} {
  repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations 1
  show
}
exit
