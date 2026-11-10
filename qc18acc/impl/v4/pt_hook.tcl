# PrimeTime report of QC18-ACC v4 (QC_PT_HOOK for QA_V=4): the shared pt_hook.tcl (QA_PT_HOOK_BASE), then
#   path_class   whether the worst setup path starts / ends at a macro pin (ARCH v4 target: inside logic)
#   path_logic   worst path with neither end at a macro
#   path_macro_q worst path from a macro (CLK -> Q) and path_macro_in worst path into a macro pin
#   hold_wp      worst hold slack into the weight / param macro inputs (min delay QA_MACRO_MIN)
#   tt only:     area groups (leaf-cell areas) for the v4 area breakdown -> $out/rpt/area_groups.txt
source $::env(QA_PT_HOOK_BASE)
set qa_m [get_cells -quiet -hierarchical -filter "is_hierarchical==false && (ref_name=~qa_act_* || ref_name=~qa_wgt_* || ref_name=~qa_par_* || ref_name=~qa_dsc_*)"]
set qa_mp [get_pins -quiet -of_objects $qa_m]
proc qa_is_macro {o} {
    set c [get_cells -quiet -of_objects $o]
    if {![sizeof_collection $c]} { return 0 }
    return [regexp {^qa_(act|wgt|par|dsc)_} [get_attribute $c ref_name]]
}
set p [get_timing_paths -delay_type max -max_paths 1 -group qa_clk]
if {[sizeof_collection $p]} {
    set sp [get_attribute $p startpoint]; set ep [get_attribute $p endpoint]
    puts $fh [format "path_class start_at_macro %d end_at_macro %d slack_ns %.3f %s -> %s" [qa_is_macro $sp] [qa_is_macro $ep] \
        [get_attribute $p slack] [get_object_name $sp] [get_object_name $ep]]
}
set nm [remove_from_collection [all_registers] $qa_m]
set q [get_timing_paths -delay_type max -max_paths 1 -from $nm -to $nm]
if {[sizeof_collection $q]} {
    puts $fh [format "path_logic slack_ns %.3f fmax_mhz %.1f %s -> %s" [get_attribute $q slack] \
        [expr {1000.0 / ([get_attribute [get_clocks qa_clk] period] - [get_attribute $q slack])}] \
        [get_object_name [get_attribute $q startpoint]] [get_object_name [get_attribute $q endpoint]]]
}
foreach {k a} [list path_macro_q [list -from $qa_m] path_macro_in [list -to [get_pins -of $qa_m -filter "direction==in"]]] {
    set q [get_timing_paths -delay_type max -max_paths 1 {*}$a]
    if {[sizeof_collection $q]} {
        puts $fh [format "%s slack_ns %.3f %s -> %s" $k [get_attribute $q slack] \
            [get_object_name [get_attribute $q startpoint]] [get_object_name [get_attribute $q endpoint]]]
    }
}
set qa_wp [get_cells -quiet -hierarchical -filter "is_hierarchical==false && (ref_name=~qa_wgt_* || ref_name=~qa_par_*)"]
set q [get_timing_paths -delay_type min -max_paths 1 -to [get_pins -of $qa_wp -filter "direction==in"]]
if {[sizeof_collection $q]} {
    puts $fh [format "hold_wp slack_ns %.3f %s -> %s (min delay %s ns)" [get_attribute $q slack] \
        [get_object_name [get_attribute $q startpoint]] [get_object_name [get_attribute $q endpoint]] [qc_env QA_MACRO_MIN 0]]
}
redirect $out/rpt/pt_${corner}_macro_boundary.rpt {
    report_timing -from $qa_m -max_paths 5 -nosplit
    report_timing -to [get_pins -of $qa_m -filter "direction==in"] -max_paths 5 -nosplit
    report_timing -delay_type min -to [get_pins -of $qa_wp -filter "direction==in"] -max_paths 5 -nosplit
}
if {$corner eq "tt"} { source [file join [file dirname $::env(QC_PT_HOOK)] area_groups.tcl] }
