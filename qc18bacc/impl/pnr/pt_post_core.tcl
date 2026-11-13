# PrimeTime post-route timing of a core.cfg run at one corner (qc18bacc/impl/pnr/run.sh pt), as
# flow/tsmc65/pnr/pt_post.tcl (routed flat netlist, def2spef SPEF, design SDC regenerated for the corner, propagated
# clock) + the fmax lines of qc18acc/pnr/pt_post_qa.tcl for clock qb_clk:
#   all      worst setup path incl. IO (IO delays are relative to the ideal clock edge: pessimistic by the latency)
#   reg2reg  worst setup path between clocked cells, IO excluded; hold_reg2reg likewise
# fmax = 1 / (period - WNS).  rpt/pt_post_<c>_reg2reg.rpt has -input_pins (wire delays as rows, wire_share.py).
set t0 [clock seconds]
source $::env(QC_FLOW)/common/lib.tcl
set top    $::env(QC_TOP)
set corner $::env(QC_CORNER)
set dir    $::env(QC_PNR_OUT)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner]]
set_app_var read_parasitics_load_locations true
read_verilog $dir/out/$top.v
current_design $top
link_design
qc_apply_constraints $corner
set_propagated_clock [all_clocks]
read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef
update_timing
file mkdir $dir/rpt
report_annotated_parasitics -list_not_annotated -max_nets 20 > $dir/rpt/pt_post_${corner}_annotation.rpt
set fh [open $dir/pt_post_$corner.txt w]
redirect -variable ann { report_annotated_parasitics }
set nets NA
if {[regexp {\n\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|} $ann -> tot rc na]} {
    set nets "total $tot rc_network $rc not_annotated $na"
}
puts $fh "design $top corner $corner lib $::QC_LIB($corner) spef_nets $nets"
qc_put_timing $fh
set per [get_attribute [get_clocks qb_clk] period]
proc fl {fh k p per} {
    if {![sizeof_collection $p]} { puts $fh "$k none"; return }
    set s [get_attribute $p slack]
    puts $fh [format "%s wns_ns %.3f fmax_mhz %.1f path %s -> %s" $k $s [expr {1000.0 / ($per - $s)}] \
        [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
}
set io [add_to_collection [all_inputs] [all_outputs]]
fl $fh all [get_timing_paths -delay_type max -max_paths 1] $per
fl $fh reg2reg [get_timing_paths -delay_type max -max_paths 1 -exclude $io] $per
fl $fh hold_reg2reg [get_timing_paths -delay_type min -max_paths 1 -exclude $io] $per
redirect -variable hv { report_constraint -min_delay -all_violators -nosplit }
puts $fh "hold_violating_endpoints [regexp -all -line {VIOLATED} $hv]"
redirect $dir/rpt/pt_post_${corner}_reg2reg.rpt { report_timing -max_paths 5 -nosplit -exclude $io -input_pins -nets -capacitance -transition_time }
redirect $dir/rpt/pt_post_${corner}_all.rpt { report_timing -max_paths 3 -nosplit -input_pins }
redirect $dir/rpt/pt_post_${corner}_min.rpt { report_timing -delay_type min -max_paths 3 -nosplit -exclude $io -path_type full_clock_expanded -input_pins }
redirect -variable lat { report_clock_timing -type latency -nworst 1 -nosplit }
puts $fh "clock_latency_worst [string map {"\n" " | "} [string range [regsub -all {\s+} [regsub {^.*?-{5,}} $lat ""] " "] 0 300]]"
redirect -variable sk { report_clock_timing -type skew -nworst 1 -nosplit }
puts $fh "clock_skew_worst [string map {"\n" " | "} [string range [regsub -all {\s+} [regsub {^.*?-{5,}} $sk ""] " "] 0 300]]"
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
if {[qc_env QB_PT_DIAG 0]} { source [file dirname [info script]]/pt_diag.tcl }
exit
