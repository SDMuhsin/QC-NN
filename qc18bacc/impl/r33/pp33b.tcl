set f [open $::env(R31_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
redirect /tmp/ckp908/qc18bacc/r33/r33_hoy_$corner.rpt { report_timing -max_paths 1 -to [get_ports u_top_s_wa_3_] -path_type full_clock_expanded -input_pins -nets -capacitance -transition_time -nosplit -significant_digits 3 }
# clock latency distribution at register clock pins
set lat {}
foreach_in_collection p [get_pins -of [all_registers -edge_triggered] -filter "is_clock_pin==true"] { set a [get_attribute -quiet $p max_rise_arrival]; if {$a ne ""} { lappend lat $a } }
set lat [lsort -real $lat]; set n [llength $lat]
puts "R33LAT $corner n $n p1 [lindex $lat [expr {$n/100}]] p10 [lindex $lat [expr {$n/10}]] p50 [lindex $lat [expr {$n/2}]] p90 [lindex $lat [expr {$n*9/10}]] p99 [lindex $lat [expr {$n*99/100}]] max [lindex $lat end]"
exit
