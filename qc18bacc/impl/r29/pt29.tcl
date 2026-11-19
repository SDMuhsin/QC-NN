# R29 timing measurement (no fixes) of a routed hub in PrimeTime: the setup part of impl/r21/pt_hub.tcl (up to the
# ETM branch) is evaluated as is, then: the not-annotated nets (rpt/r29_notann.rpt), the 3 worst reg2reg paths with
# pins / nets / cap / slew (rpt/r29_r2r3.rpt), and whether any net of those paths is not annotated.
set f [open $::env(R29_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
redirect $dir/rpt/r29_notann.rpt { report_annotated_parasitics -list_not_annotated -max_nets 100000 }
set io [add_to_collection [all_inputs] [all_outputs]]
set ps [get_timing_paths -delay_type max -max_paths 3 -nworst 1 -exclude $io]
redirect $dir/rpt/r29_r2r3.rpt { report_timing -max_paths 3 -nworst 1 -nosplit -exclude $io -input_pins -nets -capacitance -transition_time -physical }
set k 0
foreach_in_collection p $ps {
    incr k; set nets {}
    foreach_in_collection pt [get_attribute $p points] {
        set o [get_attribute $pt object]
        if {[get_attribute -quiet $o object_class] eq "pin"} { foreach_in_collection n [get_nets -quiet -of_objects $o] { lappend nets [get_object_name $n] } }
    }
    set nets [lsort -unique $nets]
    redirect -variable a { report_annotated_parasitics -list_not_annotated [get_nets $nets] }
    puts "R29PT path $k slack [get_attribute $p slack] nets [llength $nets] not_annotated_lines [regexp -all -line {^\s*\S+\s*$} $a]"
    puts "R29PT path $k nets: $nets"
}
exit
