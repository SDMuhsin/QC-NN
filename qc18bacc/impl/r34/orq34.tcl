# R34: OpenROAD sign-off view of a routed run (finish.odb + the run's own OR SPEF out/qb_hub_tt.spef, QC_SPEF_ORFIX):
# setup WNS / violators, internal-only (IO max delays relaxed) WNS / violators, worst internal path report
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
qc_read_liberty
read_db $::OUT/db/finish.odb
read_sdc $::OUT/db/finish.sdc
set_propagated_clock [all_clocks]
set per [get_property [get_clocks qb_clk] period]; set L $::env(QB_IO_LAT)
source $::env(QB_IO_BUDGET); qb5_io_apply $per $L
set t [clock seconds]
if {[catch {read_spef $::OUT/out/qb_hub_tt.spef} e]} { puts "ORQ34 read_spef ERROR $e" } else { puts "ORQ34 read_spef ok [expr {[clock seconds]-$t}] s" }
puts [format "ORQ34 all wns %.3f viol %d" [expr {[sta::worst_slack_cmd max]*1e9}] [sta::endpoint_violation_count max]]
set _ck {}; foreach c [all_clocks] { foreach sp [get_property $c sources] { lappend _ck [get_full_name $sp] } }
set _in {}; foreach pt [all_inputs] { if {[get_full_name $pt] ni $_ck && [get_full_name $pt] ne "rst_n"} { lappend _in $pt } }
set_input_delay -max [expr {-2.0 * $per}] -clock qb_clk $_in; set_output_delay -max [expr {-2.0 * $per}] -clock qb_clk [all_outputs]
puts [format "ORQ34 internal wns %.3f viol %d" [expr {[sta::worst_slack_cmd max]*1e9}] [sta::endpoint_violation_count max]]
report_checks -path_delay max -format full_clock_expanded -fields {input_pins slew cap fanout} -digits 3 > $::env(ORQ_RPT)
exit
