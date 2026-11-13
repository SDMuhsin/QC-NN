# Diagnosis of the routed reg2reg paths (results/pnr_core.md section on fmax), sourced by pt_post_core.tcl when
# QB_PT_DIAG=1 (design timed with the SPEF, $io = IO ports, $per, $dir, $corner):  over the worst path per endpoint
# (up to 20 000 reg2reg endpoints), the share of paths through OpenROAD repair buffers (wireN / splitN ..., the
# long-wire repeaters) and the worst path without any repair buffer (fmax if the repeater-chain paths were fixed).
set ps [get_timing_paths -delay_type max -max_paths 20000 -nworst 1 -slack_lesser_than 0.0 -exclude $io]
set n 0; set nrep 0; set best ""
foreach_in_collection p $ps {
    incr n
    set r 0
    foreach_in_collection pt [get_attribute $p points] {
        set nm [get_object_name [get_attribute $pt object]]
        if {[regexp {(^|/)(wire|split|max_length|rebuffer|max_cap|hold)\d+/} $nm]} { set r 1; break }
    }
    if {$r} { incr nrep } elseif {$best eq ""} { set best $p }
}
set fd [open $dir/pt_diag_$corner.txt w]
puts $fd "violating_reg2reg_endpoints $n through_repair_buffers $nrep"
if {$best ne ""} {
    set s [get_attribute $best slack]
    puts $fd [format "worst_without_repair_buffers wns_ns %.3f fmax_mhz %.1f path %s -> %s" $s [expr {1000.0 / ($per - $s)}] \
        [get_object_name [get_attribute $best startpoint]] [get_object_name [get_attribute $best endpoint]]]
    redirect $dir/rpt/pt_diag_${corner}_norep.rpt { report_timing -from [get_attribute $best startpoint] -to [get_attribute $best endpoint] -input_pins -nets -nosplit }
} else { puts $fd "worst_without_repair_buffers none_violating" }
close $fd
# Wire share by delay: the data-path delay of the worst reg2reg path and of the worst path without repair buffers,
# with the routed SPEF and again with zero wire parasitics (annotation removed, no wire-load model): share =
# (routed - zero-wire) / routed covers the net RC delay and the cell delay added by the wire capacitance.
set worst [get_timing_paths -delay_type max -max_paths 1 -exclude $io]
set prs [list worst $worst]
if {$best ne ""} { lappend prs norep $best }
array set dr {}
foreach {k p} $prs {
    set sp($k) [get_attribute $p startpoint]; set ep($k) [get_attribute $p endpoint]
    set dr($k) [expr {[get_attribute $p arrival] - [get_attribute $p startpoint_clock_latency]}]
}
set_app_var auto_wire_load_selection false
remove_annotated_parasitics
update_timing
set fd [open $dir/pt_diag_$corner.txt a]
foreach {k p} $prs {
    set q [get_timing_paths -delay_type max -from $sp($k) -to $ep($k)]
    set d0 [expr {[get_attribute $q arrival] - [get_attribute $q startpoint_clock_latency]}]
    puts $fd [format "zero_wire %s data_path_routed_ns %.3f data_path_zero_wire_ns %.3f wire_share_delay %.3f" $k $dr($k) $d0 \
        [expr {($dr($k) - $d0) / $dr($k)}]]
}
close $fd
