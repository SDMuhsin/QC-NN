# R21 antenna check of the routed hub in its own process (run.sh ant): check_antennas (not -verbose: the R15 PI run sat
# > 3 h in check_antennas -verbose inside the DR process) -> rpt/antenna.rpt, counts as R21_ANT.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env QB21_DB route_dr].odb
set t [clock seconds]
check_antennas -report_file $::OUT/rpt/antenna.rpt
puts "R21_ANT done [expr {[clock seconds] - $t}] s"
exit
