# R31 (results/r31.md): PrimeTime sign-off summary of a routed hub at one corner.  The setup part of impl/r21/pt_hub.tcl
# (up to the ETM branch: netlist, SPEF, SDC of the run, IO shift QB_IO_LAT) is evaluated as is, then R31PT lines:
#   ann       SPEF annotation (total / not annotated nets) and the case-analysis pin set (count, names, outputs among them)
#   cls       reg2reg / in2reg / reg2out / in2out: WNS and violating endpoints (worst path per endpoint)
#   fmax      reg2reg and all-path MHz = 1000 / (P - WNS)
#   grp       the 3 worst reg2reg start -> end groups (name stems, impl/r24 qb24_stem rule): endpoints, worst
#   worst     the worst all-path path: start / end, arrival, required, input / output external delay (IO budget)
# Env as pt_hub.tcl (impl/r31/pt31.sh).  Output: R31PT lines in the log, rpt/r31_<corner>_worst.rpt.
set f [open $::env(R31_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
set C $corner
redirect -variable ann { report_annotated_parasitics }
regexp {\n\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|} $ann -> tot rc na
puts "R31PT $C ann nets $tot rc $rc not_annotated $na"
set cp [get_pins -quiet -hierarchical * -filter "defined(user_case_value)"]
set nm {}; set nq 0
foreach_in_collection p $cp { regsub {\[.*} [get_attribute $p lib_pin_name] {} b; dict incr nm $b; if {[get_attribute $p direction] ne "in"} { incr nq } }
puts "R31PT $C user_case pins [sizeof_collection $cp] non_input $nq names $nm"
set ins [all_inputs]; set outs [all_outputs]; set io [add_to_collection $ins $outs]
proc ep {args} { return [get_timing_paths -delay_type max -max_paths 200000 -nworst 1 -slack_lesser_than 0 {*}$args] }
proc wns {args} { set p [get_timing_paths -delay_type max -max_paths 1 {*}$args]; if {[sizeof_collection $p]} { return [format %.3f [get_attribute $p slack]] }; return NA }
set r2r [ep -exclude $io]
foreach {k a} [list reg2reg [list -exclude $io] in2reg [list -from $ins -exclude $outs] reg2out [list -to $outs -exclude $ins] in2out [list -from $ins -to $outs]] {
    set n [expr {$k eq "reg2reg" ? [sizeof_collection $r2r] : [sizeof_collection [ep {*}$a]]}]
    set W($k) [wns {*}$a]
    puts "R31PT $C cls $k wns $W($k) viol_endpoints $n"
}
set W(all) [wns]
puts "R31PT $C fmax reg2reg [format %.1f [expr {1000.0 / ($per - $W(reg2reg))}]] all [format %.1f [expr {1000.0 / ($per - $W(all))}]] MHz (P $per wns $W(reg2reg) / $W(all))"
proc stem {o} { set n [get_object_name $o]; set i [string last / $n]; if {$i > 0} { set n [string range $n 0 [expr {$i - 1}]] }; return [regsub -all {_?[0-9]+_?} $n N] }
array set G {}
foreach_in_collection p $r2r {
    set k "[stem [get_attribute $p startpoint]] -> [stem [get_attribute $p endpoint]]"; set s [get_attribute $p slack]
    if {![info exists G($k)]} { set G($k) [list 0 $s] }
    lassign $G($k) c w; set G($k) [list [incr c] [expr {min($w, $s)}]]
}
set L {}; foreach k [array names G] { lappend L [list $k {*}$G($k)] }
set i 0; foreach g [lsort -real -index 2 $L] { if {[incr i] > 3} break; puts "R31PT $C grp $i [lindex $g 0] endpoints [lindex $g 1] worst [format %.3f [lindex $g 2]]" }
puts "R31PT $C grp_total [llength $L]"
set p [get_timing_paths -delay_type max -max_paths 1]
set ex {}; foreach a {startpoint_input_delay_value endpoint_output_delay_value startpoint_clock_latency endpoint_clock_latency arrival required slack} { lappend ex $a [get_attribute -quiet $p $a] }
puts "R31PT $C worst [get_object_name [get_attribute $p startpoint]] -> [get_object_name [get_attribute $p endpoint]] $ex"
redirect $dir/rpt/r31_${C}_worst.rpt { report_timing -max_paths 1 -input_pins -nets -capacitance -transition_time -nosplit }
puts "R31PT $C done [expr {[clock seconds] - $t0}] s"
exit
