set f [open $::env(R31_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
set late {}
foreach_in_collection p [get_pins -of [all_registers -edge_triggered] -filter "is_clock_pin==true"] {
  set a [get_attribute -quiet $p max_rise_arrival]; if {$a ne "" && $a > 2.0} { append_to_collection late $p }
}
set lc [get_cells -of $late]
puts "R33D $corner late regs [sizeof_collection $lc]: [lsort -unique [lmap n [get_object_name $lc] {regsub -all {_?[0-9]+_?} $n N}]]"
set io [add_to_collection [all_inputs] [all_outputs]]
proc w {args} { set p [get_timing_paths -delay_type max -max_paths 1 {*}$args]; if {[sizeof_collection $p]} { return "[format %.3f [get_attribute $p slack]] [get_object_name [get_attribute $p startpoint]] -> [get_object_name [get_attribute $p endpoint]]" }; return NA }
puts "R33D $corner all: [w]"
puts "R33D $corner from late regs: [w -from $late]"
puts "R33D $corner through late regs (to): [w -to [get_pins -of $lc -filter direction==in]]"
puts "R33D $corner all excluding late regs: [w -exclude $lc]"
puts "R33D $corner reg2out excluding late regs: [w -to [all_outputs] -exclude [add_to_collection $lc [all_inputs]]]"
puts "R33D $corner reg2reg excluding late regs: [w -exclude [add_to_collection $lc $io]]"
exit
