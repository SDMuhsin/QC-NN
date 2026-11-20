set f [open $::env(R31_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
set cc [all_fanout -clock_tree -flat -only_cells]
set tot [sizeof_collection $cc]
array set R {}
foreach_in_collection c $cc { set r [get_attribute $c ref_name]; regsub {D[0-9]+$} $r {} r; incr R($r) }
puts "R33CT $corner clock-tree cells $tot by type [array get R]"
set nb [filter_collection $cc "ref_name=~BUFF* || ref_name=~INV*"]
set pf {}; array set P {}
foreach_in_collection c $nb { regexp {^([a-z_]+)} [get_object_name $c] -> p; incr P($p) }
puts "R33CT $corner non-CK buffers/inverters in the clock tree [sizeof_collection $nb] by name prefix [array get P]"
# register clock pins downstream of a non-CK buffer: latency
set late 0; set nl 0
foreach_in_collection p [get_pins -of [all_registers -edge_triggered] -filter "is_clock_pin==true"] {
  set a [get_attribute -quiet $p max_rise_arrival]; if {$a eq ""} continue
  if {$a > 2.0} { incr late }
}
puts "R33CT $corner register clock pins with latency > 2.0 ns: $late"
set i 0
foreach_in_collection c $nb { if {[incr i] > 12} break; set o [get_pins -of $c -filter "direction==out"]; puts "R33CTL [get_object_name $c] [get_attribute $c ref_name] out_tran [get_attribute -quiet $o actual_rise_transition_max] fanout [sizeof_collection [all_fanout -from $o -flat -endpoints_only]]" }
exit
