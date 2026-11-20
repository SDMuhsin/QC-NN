set f [open $::env(R31_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
set io [add_to_collection [all_inputs] [all_outputs]]
redirect /tmp/ckp908/qc18bacc/r33/r33_r2r_$corner.rpt { report_timing -max_paths 1 -exclude $io -path_type full_clock_expanded -input_pins -nets -capacitance -transition_time -nosplit -significant_digits 3 }
redirect -append /tmp/ckp908/qc18bacc/r33/r33_r2r_$corner.rpt { report_timing -max_paths 1 -to [get_pins -hier *b2f_d_reg*/D] -path_type full_clock_expanded -input_pins -nets -capacitance -transition_time -nosplit -significant_digits 3 }
redirect /tmp/ckp908/qc18bacc/r33/r33_misc_$corner.rpt { report_design; report_timing_derate; printvar timing_*; report_clock -skew -attr; report_case_analysis -nosplit }
exit
