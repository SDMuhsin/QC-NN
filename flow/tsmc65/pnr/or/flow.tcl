# OpenROAD P&R flow (driven by pnr/run_pnr.sh).  Steps, each in its own file and ending in a checkpoint:
#   init floorplan pdn place cts route finish
# Environment: QC_PNR_CFG (design config), QC_PNR_OUT (output dir), QC_PNR_FROM / QC_PNR_TO (step range),
#   QC_PNR_THREADS.  Netlist / SDC / config are resolved by run_pnr.sh into $OUT/config.tcl.
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set f [open $::OUT/kit.env w]
foreach {k v} [list TOP [p TOP] CORNERS $::QC_CORNERS LEF $::QC_PNR_LEF GDS $::QC_PNR_GDS GDSMAP $::QC_PNR_GDSMAP \
        MACRO_LEFS [p MACRO_LEFS] MACRO_GDS [p MACRO_GDS] DO_GDS [p GDS] NETLIST [p NETLIST] SDC [p SDC]] {
    puts $f "$k=\"$v\""
}
close $f
set_thread_count [qc_env QC_PNR_THREADS 8]
set ::STEPS {init floorplan pdn place cts route finish}
set from [qc_env QC_PNR_FROM init]
set to   [qc_env QC_PNR_TO finish]
set i0 [lsearch $::STEPS $from]; set i1 [lsearch $::STEPS $to]
if {$i0 < 0 || $i1 < 0} { error "unknown step $from / $to (steps: $::STEPS)" }
if {$i0 > 0} { qc_load [lindex $::STEPS [expr {$i0 - 1}]] }
foreach s [lrange $::STEPS $i0 $i1] {
    qc_log "step $s"
    source $::env(QC_FLOW)/pnr/or/$s.tcl
    qc_save $s
}
qc_log "flow done [expr {[clock seconds] - $::T0}] s"
exit
