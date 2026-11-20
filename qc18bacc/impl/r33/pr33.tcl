# R33 path reports on a db: R33_DB step, R33_TO endpoints (pins), output R33_RPT
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set _f [open $::OUT/config.tcl]; set _t [read $_f]; close $_f
eval [string map {r31_snap/ r31_snap4/} $_t]
qc_config
set step $::env(R33_DB)
qc_read_liberty
read_db [qc_env R33_ODBIN $::OUT/db/$step.odb]
set_dont_use $::QC_PNR_DONT_USE
read_sdc $::OUT/db/$step.sdc
qc_set_rc
if {$step ne "place"} { set_propagated_clock [all_clocks] }
if {[qc_env R33_GRT 0]} { estimate_parasitics -global_routing } else { estimate_parasitics -placement }
set f $::env(R33_RPT)
report_checks -path_delay max -from [all_registers -clock_pins] -to [all_registers -data_pins] -format full_clock_expanded -fields {input_pins slew cap fanout} -digits 3 > $f
foreach p $::env(R33_TO) { report_checks -path_delay max -to [get_pins $p] -format full_clock_expanded -fields {input_pins slew cap fanout} -digits 3 >> $f }
exit
