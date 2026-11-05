# PrimeTime report of qc_snitch_cluster_top (QC_PT_HOOK of flow/tsmc65/sta/run_pt.sh; $fh = open summary).
# Per clock: worst setup slack and fmax = 1 / (period - WNS), the worst path of that clock; macro count / area;
# vectorless power (PrimePower if licensed; default activity: toggle 0.1 per cycle, static probability 0.5).
foreach c [lsort [get_object_name [all_clocks]]] {
    set per [get_attribute [get_clocks $c] period]
    set p [get_timing_paths -delay_type max -max_paths 1 -group $c]
    if {![sizeof_collection $p]} { puts $fh "clock $c period_ns $per no_paths"; continue }
    set s [get_attribute $p slack]
    puts $fh [format "clock %s period_ns %.3f wns_ns %.3f fmax_mhz %.1f path %s -> %s" $c $per $s \
        [expr {1000.0 / ($per - $s)}] [get_object_name [get_attribute $p startpoint]] \
        [get_object_name [get_attribute $p endpoint]]]
    redirect $out/rpt/pt_${corner}_${c}_max.rpt { report_timing -group $c -max_paths 5 -nosplit -input_pins -nets }
}
set mcs [get_cells -quiet -hierarchical -filter "ref_name=~qc_*"]
set ma 0.0; foreach_in_collection m $mcs { set ma [expr {$ma + [get_attribute [get_lib_cells -of $m] area]}] }
puts $fh [format "macros %d macro_area_um2 %.0f" [sizeof_collection $mcs] $ma]
if {[catch {
    set_app_var power_enable_analysis true
    set_switching_activity -static_probability 0.5 -toggle_rate 0.1 -base_clock clu_clk [all_inputs]
    set_app_var power_default_toggle_rate 0.1
    set_app_var power_default_static_probability 0.5
    update_power
    redirect $out/rpt/pt_${corner}_power.rpt { report_power -nosplit }
    redirect $out/rpt/pt_${corner}_power_hier.rpt { report_power -nosplit -hierarchy -levels 3 }
    redirect -variable pr { report_power -nosplit }
    if {[regexp -line {^\s*Total Power\s*=\s*(\S+)} $pr -> tp]} { puts $fh "power_total_w $tp (vectorless, toggle 0.1)" }
    foreach k {{Net Switching Power} {Cell Internal Power} {Cell Leakage Power}} {
        if {[regexp -line "^\\s*$k\\s*=\\s*(\\S+)" $pr -> v]} { puts $fh "power_[string map {{ } _} [string tolower $k]]_w $v" }
    }
} e]} { puts $fh "power NA ($e)" }
