# R29: full-die drt::check_drc of a routed db (R29_DB [route_dr]) -> rpt/r29_drc.rpt, count and type histogram.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/[qc_env R29_DB route_dr].odb
set_thread_count 8
drt::check_drc -output_file $::OUT/rpt/r29_drc.rpt
set g [open $::OUT/rpt/r29_drc.rpt]; set t [read $g]; close $g
puts "R29_DRC full-die violations [regexp -all {violation type} $t]"
foreach l [split $t \n] { if {[regexp {violation type: (.*)} $l -> ty]} { dict incr h [string trim $ty] } }
if {[info exists h]} { dict for {k v} $h { puts "R29_DRC type $k $v" } }
exit
