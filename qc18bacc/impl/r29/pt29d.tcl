# R29: reg2reg in PT with and without the macro QA pins that OpenROAD's SDC expansion sets constant
# (set_case_analysis 0 lines on */QA[*] pins in db/grt.sdc): worst slack, violators, and the 3 worst of each set.
set f [open $::env(R29_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
set qa {}; set g [open $dir/db/grt.sdc]
while {[gets $g l] >= 0} { if {[regexp {^set_case_analysis 0 \[get_pins \{(\S+/QA\[\d+\])\}\]} $l -> p]} { lappend qa $p } }
close $g
set qp [get_pins $qa]
set io [add_to_collection [all_inputs] [all_outputs]]
foreach {k ex} [list all $io noqa [add_to_collection $io $qp]] {
    set ps [get_timing_paths -delay_type max -max_paths 3 -nworst 1 -exclude $ex]
    foreach_in_collection p $ps { puts [format "R29PTD %s slack %.3f %s -> %s" $k [get_attribute $p slack] [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]] }
}
set ps [get_timing_paths -delay_type max -max_paths 100000 -nworst 1 -slack_lesser_than 0 -exclude $io]
set n 0; set nq 0
foreach_in_collection p $ps { incr n; foreach_in_collection pt [get_attribute $p points] { if {[lsearch -exact $qa [get_object_name [get_attribute $pt object]]] >= 0} { incr nq; break } } }
puts "R29PTD qa_pins [sizeof_collection $qp] reg2reg_violating_endpoints $n through_qa $nq"
exit
