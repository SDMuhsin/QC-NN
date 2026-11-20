# R31: clock-path diagnosis in PrimeTime (impl/r31/pt31.sh <tag> <corner> with R31_PTT=clk31.tcl): the setup part of
# impl/r21/pt_hub.tcl, then for the worst all-path path and the worst hold path: report_timing -path_type
# full_clock_expanded (rpt/r31_<corner>_clk_{setup,hold}.rpt), and the clock-latency distribution over all register
# clock pins (R31CLK lines: count, p10 / p50 / p90 / max, the 5 latest pins).
set f [open $::env(R31_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
set C $corner
redirect $dir/rpt/r31_${C}_clk_setup.rpt { report_timing -path_type full_clock_expanded -max_paths 1 -nets -transition_time -capacitance -input_pins -nosplit }
redirect $dir/rpt/r31_${C}_clk_hold.rpt { report_timing -delay_type min -path_type full_clock_expanded -max_paths 1 -nets -transition_time -capacitance -input_pins -nosplit }
set L {}
    foreach_in_collection p [get_pins -quiet [all_registers -clock_pins]] {
        set w [get_attribute -quiet $p max_rise_arrival]; if {$w ne ""} { lappend L [list $w [get_object_name $p]] }
    }
set L [lsort -real -index 0 $L]; set n [llength $L]
if {$n} {
    set q {}; foreach f {0.1 0.5 0.9} { lappend q [format %.3f [lindex $L [expr {int($f * ($n - 1))}] 0]] }
    puts "R31CLK $C pins $n p10/p50/p90 $q max [format %.3f [lindex $L end 0]]"
    foreach e [lrange $L end-4 end] { puts "R31CLK $C late [format %.3f [lindex $e 0]] [lindex $e 1]" }
    set h {}; foreach e $L { set b [expr {int([lindex $e 0] / 0.25)}]; dict incr h $b }
    puts "R31CLK $C hist_0.25ns [lmap k [lsort -integer [dict keys $h]] {format %.2f:%d [expr {$k * 0.25}] [dict get $h $k]}]"
} else { puts "R31CLK $C no latency attribute" }
exit
