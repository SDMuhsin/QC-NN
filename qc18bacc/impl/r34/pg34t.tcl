# R34 syntax test of post_grt.tcl's IO false-path commands on a run's cts_rt db
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load cts_rt
set_thread_count 1
set _ck {}; foreach c [all_clocks] { foreach sp [get_property $c sources] { lappend _ck [get_full_name $sp] } }
set _in {}; foreach pt [all_inputs] { if {[get_full_name $pt] ni $_ck} { lappend _in $pt } }
set _out [all_outputs]
puts "PG34 ck $_ck in [llength $_in] of [llength [all_inputs]] out [llength $_out]"
estimate_parasitics -placement
puts "PG34 before wns [sta::worst_slack_cmd max] viol [sta::endpoint_violation_count max] hold [sta::endpoint_violation_count min]"
set_false_path -from $_in; set_false_path -to $_out
puts "PG34 fp wns [sta::worst_slack_cmd max] viol [sta::endpoint_violation_count max]"
unset_path_exceptions -from $_in; unset_path_exceptions -to $_out
puts "PG34 unset wns [sta::worst_slack_cmd max] viol [sta::endpoint_violation_count max]"
exit
