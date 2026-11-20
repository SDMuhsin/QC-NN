# R31: hold breakdown in PrimeTime (impl/r31/pt31.sh <tag> <corner> with R31_PTT=hold31): the setup part of
# impl/r21/pt_hub.tcl, then R31HOLD lines: violating endpoints per class (reg2reg / in2reg / reg2out / in2out),
# slack histogram (0.05 ns bins), the 5 worst reg2reg start -> end stem groups, and for violating reg2reg endpoints
# the mean capture - launch clock latency difference (skew) vs the mean data delay.
set f [open $::env(R31_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
set C $corner
set ins [all_inputs]; set outs [all_outputs]; set io [add_to_collection $ins $outs]
proc hp {args} { return [get_timing_paths -delay_type min -max_paths 200000 -nworst 1 -slack_lesser_than 0 {*}$args] }
foreach {k a} [list reg2reg [list -exclude $io] in2reg [list -from $ins -exclude $outs] reg2out [list -to $outs -exclude $ins] in2out [list -from $ins -to $outs]] {
    set P($k) [hp {*}$a]; puts "R31HOLD $C cls $k viol_endpoints [sizeof_collection $P($k)]"
}
array set H {}; set sk 0.0; set dd 0.0; set n 0
proc stem {o} { set n [get_object_name $o]; set i [string last / $n]; if {$i > 0} { set n [string range $n 0 [expr {$i - 1}]] }; return [regsub -all {_?[0-9]+_?} $n N] }
array set G {}
foreach_in_collection p $P(reg2reg) {
    set s [get_attribute $p slack]; set b [expr {int(floor($s / 0.05))}]; if {[info exists H($b)]} { incr H($b) } else { set H($b) 1 }
    set lc [get_attribute -quiet $p startpoint_clock_latency]; set cc [get_attribute -quiet $p endpoint_clock_latency]
    if {$lc ne "" && $cc ne ""} { set sk [expr {$sk + $cc - $lc}]; set dd [expr {$dd + [get_attribute $p arrival] - $lc}]; incr n }
    set k "[stem [get_attribute $p startpoint]] -> [stem [get_attribute $p endpoint]]"
    if {![info exists G($k)]} { set G($k) [list 0 $s] }
    lassign $G($k) c w; set G($k) [list [incr c] [expr {min($w, $s)}]]
}
puts "R31HOLD $C reg2reg_hist [lmap b [lsort -integer [array names H]] {format %.2f:%d [expr {$b * 0.05}] $H($b)}]"
if {$n} { puts "R31HOLD $C reg2reg mean capture-launch latency [format %.3f [expr {$sk / $n}]] mean arrival-launch [format %.3f [expr {$dd / $n}]] n $n" }
set L {}; foreach k [array names G] { lappend L [list $k {*}$G($k)] }
set i 0; foreach g [lsort -integer -decreasing -index 1 $L] { if {[incr i] > 6} break; puts "R31HOLD $C grp [lindex $g 0] endpoints [lindex $g 1] worst [format %.3f [lindex $g 2]]" }
exit
