# R34 OR SPEF read test: finish.odb + sdc of run QC_PNR_OUT, read_spef R34_SPEF, then timing summary
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set _f [open $::OUT/config.tcl]; set _t [read $_f]; close $_f
eval [string map {r31_snap/ r31_snap4/} $_t]
qc_config
qc_read_liberty
read_db $::OUT/db/finish.odb
read_sdc $::OUT/db/finish.sdc
set_propagated_clock [all_clocks]
set L $::env(QB_IO_LAT); set per [get_property [get_clocks qb_clk] period]
source $::env(QB_IO_BUDGET); qb5_io_apply $per $L
set t [clock seconds]
if {[catch {read_spef $::env(R34_SPEF)} e]} { puts "R34S read_spef ERROR $e" } else { puts "R34S read_spef ok [expr {[clock seconds]-$t}] s" }
set pe [lindex [find_timing_paths -from [all_registers -clock_pins] -to [all_registers -data_pins] -path_delay max -group_count 1] 0]
puts [format "R34S reg2reg wns %.3f" [expr {[$pe slack]*1e9}]]
puts [format "R34S all wns %.3f viol %d" [expr {[sta::worst_slack_cmd max]*1e9}] [sta::endpoint_violation_count max]]
set n 0; set nl 0; set s 0.0
foreach p [all_registers -clock_pins] { if {[incr n] % 50} continue; set a [get_property $p arrival_max_rise]; if {$a eq "" || $a eq "INF"} continue; incr nl; set s [expr {$s + $a}] }
puts [format "R34S mean clk latency (1/50 sample) %.3f n %d" [expr {$s/$nl}] $nl]
report_checks -path_delay max -group_count 1 -format full_clock_expanded -digits 3 > $::env(R34_RPT)
exit
