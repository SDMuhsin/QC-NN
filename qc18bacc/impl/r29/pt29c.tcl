# R29: clock paths of the 3 worst reg2reg paths (full_clock_expanded) and the annotation state of every net on them.
set f [open $::env(R29_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
set io [add_to_collection [all_inputs] [all_outputs]]
redirect $dir/rpt/r29_r2r3_clk.rpt { report_timing -max_paths 3 -nworst 1 -nosplit -exclude $io -path_type full_clock_expanded -input_pins -nets -transition_time -capacitance }
redirect -variable na { report_annotated_parasitics -list_not_annotated -max_nets 100000 }
set nab {}; foreach l [split $na \n] { if {[regexp {^\s*\d+\.\s+(\S+)} $l -> n]} { dict set nab $n 1 } }
set g [open $dir/rpt/r29_r2r3_clk.rpt]; set k 0; set tot 0; set bad 0
while {[gets $g l] >= 0} {
    if {[regexp {^\s*Startpoint} $l]} { if {$k} { puts "R29PTC path $k nets $tot not_annotated $bad" }; incr k; set tot 0; set bad 0 }
    if {[regexp {^\s*(\S+) \(net\)} $l -> n]} { incr tot; if {[dict exists $nab $n]} { incr bad; puts "R29PTC path $k not-annotated net $n" } }
}
close $g; puts "R29PTC path $k nets $tot not_annotated $bad"
exit
