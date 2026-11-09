# PrimeTime report of QC18-ACC (QC_PT_HOOK of flow/tsmc65/sta/run_pt.sh; $fh = open summary, $out, $corner).
# fmax = 1 / (period - WNS) of the worst setup path (setup uncertainty included); worst path reports (all, into /
# out of macros); macro count / area.  No power here (activity-based power is a later step on the GLS SAIF).
set per [get_attribute [get_clocks qa_clk] period]
set p [get_timing_paths -delay_type max -max_paths 1 -group qa_clk]
if {[sizeof_collection $p]} {
    set s [get_attribute $p slack]
    puts $fh [format "clock qa_clk period_ns %.3f wns_ns %.3f fmax_mhz %.1f path %s -> %s" $per $s \
        [expr {1000.0 / ($per - $s)}] [get_object_name [get_attribute $p startpoint]] \
        [get_object_name [get_attribute $p endpoint]]]
}
redirect $out/rpt/pt_${corner}_qa_clk_max.rpt { report_timing -group qa_clk -max_paths 20 -nworst 1 -slack_lesser_than 100 -nosplit -input_pins -nets }
set mcs [get_cells -quiet -hierarchical -filter "is_hierarchical==false && (ref_name==qa_act_1024x64m8 || ref_name==qa_wgt_4096x80m8 || ref_name==qa_par_4096x72m8 || ref_name==qa_dsc_256x32m2)"]
foreach {k a} [list to_macro [list -to [get_pins -of $mcs -filter "direction==in"]] from_macro [list -from $mcs]] {
    if {![catch {set q [get_timing_paths -delay_type max -max_paths 1 {*}$a]}] && [sizeof_collection $q]} {
        puts $fh [format "path_%s slack_ns %.3f %s -> %s" $k [get_attribute $q slack] \
            [get_object_name [get_attribute $q startpoint]] [get_object_name [get_attribute $q endpoint]]]
    }
}
# worst path per hierarchy endpoint group (first-level instance of the endpoint)
redirect $out/rpt/pt_${corner}_endpoints.rpt {
    foreach_in_collection q [get_timing_paths -delay_type max -max_paths 2000 -nworst 1] {
        puts [format "%.3f %s %s" [get_attribute $q slack] [get_object_name [get_attribute $q startpoint]] \
            [get_object_name [get_attribute $q endpoint]]]
    }
}
set ma 0.0; foreach_in_collection m $mcs { set ma [expr {$ma + [get_attribute [get_lib_cells -of $m] area]}] }
puts $fh [format "macros %d macro_area_um2 %.0f" [sizeof_collection $mcs] $ma]
