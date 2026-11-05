# PrimeTime report of the KUL cluster (QC_PT_HOOK of flow/tsmc65/sta/run_pt.sh; $fh = open summary).
# fmax = 1 / (period - WNS) of the worst setup path (setup uncertainty included); worst path reports; macro count /
# area; vectorless power (default activity: toggle 0.1 per cycle, static probability 0.5).
set per [get_attribute [get_clocks clu_clk] period]
set p [get_timing_paths -delay_type max -max_paths 1 -group clu_clk]
if {[sizeof_collection $p]} {
    set s [get_attribute $p slack]
    puts $fh [format "clock clu_clk period_ns %.3f wns_ns %.3f fmax_mhz %.1f path %s -> %s" $per $s \
        [expr {1000.0 / ($per - $s)}] [get_object_name [get_attribute $p startpoint]] \
        [get_object_name [get_attribute $p endpoint]]]
}
redirect $out/rpt/pt_${corner}_clu_clk_max.rpt { report_timing -group clu_clk -max_paths 10 -nworst 1 -slack_lesser_than 100 -nosplit -input_pins -nets }
# worst path per endpoint class: into macros, from macros, reg -> reg
foreach {k from to} {to_macro "" kul from_macro kul ""} {
    set args [list -delay_type max -max_paths 1]
    if {$from ne ""} { lappend args -from [get_cells -hierarchical -filter "ref_name=~kul_rf_*"] }
    if {$to ne ""}   { lappend args -to   [get_pins -of [get_cells -hierarchical -filter "ref_name=~kul_rf_*"] -filter "direction==in"] }
    if {![catch {set q [get_timing_paths {*}$args]}] && [sizeof_collection $q]} {
        puts $fh [format "path_%s slack_ns %.3f %s -> %s" $k [get_attribute $q slack] \
            [get_object_name [get_attribute $q startpoint]] [get_object_name [get_attribute $q endpoint]]]
    }
}
set mcs [get_cells -quiet -hierarchical -filter "ref_name=~kul_rf_*"]
set ma 0.0; foreach_in_collection m $mcs { set ma [expr {$ma + [get_attribute [get_lib_cells -of $m] area]}] }
puts $fh [format "macros %d macro_area_um2 %.0f" [sizeof_collection $mcs] $ma]
if {[catch {
    set_app_var power_enable_analysis true
    set_app_var power_default_toggle_rate 0.1
    set_app_var power_default_static_probability 0.5
    set_switching_activity -static_probability 0.5 -toggle_rate 0.1 -base_clock clu_clk [remove_from_collection [all_inputs] [get_ports clk_i]]
    update_power
    redirect $out/rpt/pt_${corner}_power.rpt { report_power -nosplit }
    redirect $out/rpt/pt_${corner}_power_hier.rpt { report_power -nosplit -hierarchy -levels 4 }
    redirect -variable pr { report_power -nosplit }
    if {[regexp -line {^\s*Total Power\s*=\s*(\S+)} $pr -> tp]} { puts $fh "power_total_w $tp (vectorless, toggle 0.1, at period $per ns)" }
    foreach k {{Net Switching Power} {Cell Internal Power} {Cell Leakage Power}} {
        if {[regexp -line "^\\s*$k\\s*=\\s*(\\S+)" $pr -> v]} { puts $fh "power_[string map {{ } _} [string tolower $k]]_w $v" }
    }
} e]} { puts $fh "power NA ($e)" }
