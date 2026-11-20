# R34 test: IO false paths set + unset, then the r9b post_grt reports (timed); R34_MODE fp | relax
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load cts_rt
estimate_parasitics -placement
set per [get_property [get_clocks qb_clk] period]; set L $::env(QB_IO_LAT)
set _ck {}; foreach c [all_clocks] { foreach sp [get_property $c sources] { lappend _ck [get_full_name $sp] } }
set _in {}; foreach pt [all_inputs] { if {[get_full_name $pt] ni $_ck} { lappend _in $pt } }
set _out [all_outputs]
set t [clock seconds]
puts "PG34U base wns [sta::worst_slack_cmd max] viol [sta::endpoint_violation_count max] ([expr {[clock seconds]-$t}] s)"
if {$::env(R34_MODE) eq "fp"} {
    set_false_path -from $_in; set_false_path -to $_out
    puts "PG34U fp wns [sta::worst_slack_cmd max] viol [sta::endpoint_violation_count max] ([expr {[clock seconds]-$t}] s)"
    unset_path_exceptions -from $_in; unset_path_exceptions -to $_out
} else {
    set_input_delay [expr {-2.0 * $per}] -clock qb_clk $_in; set_output_delay [expr {-2.0 * $per}] -clock qb_clk $_out
    puts "PG34U relax wns [sta::worst_slack_cmd max] viol [sta::endpoint_violation_count max] ([expr {[clock seconds]-$t}] s)"
    source $::env(QB_IO_BUDGET); qb5_io_apply $per $L
}
puts "PG34U restored wns [sta::worst_slack_cmd max] viol [sta::endpoint_violation_count max] ([expr {[clock seconds]-$t}] s)"
report_checks -path_delay max -format full_clock_expanded -fields {input_pins slew cap fanout} -digits 3 -group_count 20 -endpoint_count 1 > /tmp/ckp908/qc18bacc/r34/pg34u_$::env(R34_MODE).rpt
puts "PG34U report done ([expr {[clock seconds]-$t}] s)"
exit
