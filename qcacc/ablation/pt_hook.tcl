# QC_PT_HOOK of flow/tsmc65/sta/pt.tcl for the ablation cores: worst register-to-register setup slack
# (excludes the IO paths that carry the 20 % IO delays) and vectorless total power, into the corner summary $fh.
set p [get_timing_paths -delay_type max -max_paths 1 -from [all_registers -clock_pins] -to [all_registers -data_pins]]
if {[sizeof_collection $p]} {
  puts $fh "reg2reg_setup_slack_ns [get_attribute $p slack] [get_object_name [get_attribute $p startpoint]] -> [get_object_name [get_attribute $p endpoint]]"
}
foreach {k from to} {in2reg in reg reg2out reg out} {
  set f [expr {$from eq "in" ? [all_inputs] : [all_registers -clock_pins]}]
  set t [expr {$to eq "out" ? [all_outputs] : [all_registers -data_pins]}]
  set q [get_timing_paths -delay_type max -max_paths 1 -from $f -to $t]
  if {[sizeof_collection $q]} { puts $fh "${k}_setup_slack_ns [get_attribute $q slack]" }
}
