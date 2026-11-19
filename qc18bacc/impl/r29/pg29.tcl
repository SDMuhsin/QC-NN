# R29: check_power_grid VDD / VSS on a routed db (R29_DB [route_dr]) after the opt-in macro-PDN trim (pdn29.tcl).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/[qc_env R29_DB route_dr].odb
foreach n [list $::QC_PNR_PWR $::QC_PNR_GND] { if {[catch {check_power_grid -net $n} r]} { puts "R29_PG $n FAIL $r" } else { puts "R29_PG $n $r" } }
exit
