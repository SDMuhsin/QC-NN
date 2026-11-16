# R10b: GRT run-time probe on a checkpoint (read only): QB_DB [cts] of run QC_PNR_OUT, global_route -verbose with
# QB_GI [3] congestion iterations, optional congestion report (QB_GREP 0/1), timestamps per phase -> stdout.
# Env knobs: QB_GADJ [0.25] layer adjustment, QB_GCRIT 0/1 critical-nets percentage 0, QB_GOUT (guide/report dir).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set_thread_count [qc_env QC_PNR_THREADS 8]
set t0 [clock milliseconds]
proc ts {m} { puts [format "R10B_T %7.1f s %s" [expr {([clock milliseconds] - $::t0) / 1000.0}] $m]; flush stdout }
qc_load [qc_env QB_DB cts]
ts loaded
set blk [ord::get_db_block]
set ni 0; set nb 0; set nn 0; set npin 0; set big 0
foreach n [$blk getNets] { set st [$n getSigType]; if {$st eq "POWER" || $st eq "GROUND"} continue
    incr nn; set k [expr {[llength [$n getITerms]] + [llength [$n getBTerms]]}]; incr npin $k; if {$k > 64} { incr big } }
ts "nets $nn pins $npin nets>64pins $big insts [llength [$blk getInsts]] bterms [llength [$blk getBTerms]]"
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [qc_env QB_GADJ 0.25]
if {[qc_env QB_GCRIT 0]} { set_global_routing -critical_nets_percentage 0 }
set od [qc_env QB_GOUT $::OUT]
set a [list -congestion_iterations [qc_env QB_GI 3] -allow_congestion -verbose]
if {[qc_env QB_GREP 0]} { lappend a -congestion_report_file $od/gr_cong_probe.rpt }
if {[qc_env QB_GGUIDE 0]} { lappend a -guide_file $od/probe.guide }
ts "global_route $a"
global_route {*}$a
ts "global_route done"
if {[qc_env QB_GPAR 0]} { estimate_parasitics -global_routing; ts "estimate_parasitics done" }
exit
