# PrimeTime sign-off of the hardened-PE column at one corner (results/pnr_pe.md): routed column netlist with the 16
# PE instances linked to the block ETM of that corner (pe_etm.tcl), def2spef SPEF of the column, propagated clock;
# then the report / fmax lines of impl/pnr/pt_post_core.tcl (all, reg2reg, hold).  The block's internal reg2reg is
# signed off separately (its own routed SPEF); column fmax = min of the two.
source $::env(QC_FLOW)/common/lib.tcl
set top $::env(QC_TOP); set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] $::env(QB_HB_ETM_DIR)/qb_pe_hb_${corner}_lib.db]
set_app_var read_parasitics_load_locations true
read_verilog $dir/out/$top.v
current_design $top
link_design
qc_apply_constraints $corner
set_propagated_clock [all_clocks]
read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef
update_timing
file mkdir $dir/rpt
report_annotated_parasitics -list_not_annotated -max_nets 20 > $dir/rpt/pt_col_${corner}_annotation.rpt
set fh [open $dir/pt_col_$corner.txt w]
puts $fh "design $top corner $corner lib $::QC_LIB($corner) etm $::env(QB_HB_ETM_DIR)/qb_pe_hb_${corner}_lib.db"
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
fl $fh hold_all [get_timing_paths -delay_type min -max_paths 1] $per
redirect -variable hv { report_constraint -min_delay -all_violators -nosplit }
puts $fh "hold_violating_endpoints [regexp -all -line {VIOLATED} $hv]"
# worst reg2reg per class: endpoint inside a PE block (ETM pin), BR / decoders, fused lanes, wide lanes
foreach {cl pat} {to_pe *u_pe/* br_dec *u_br* lane_f *u_lf* lane_w *u_lw*} {
    set p [get_timing_paths -delay_type max -max_paths 1 -exclude $io -to [get_pins -quiet -hierarchical $pat -filter "direction==in"]]
    fl $fh class_$cl $p $per
}
redirect $dir/rpt/pt_col_${corner}_reg2reg.rpt { report_timing -max_paths 5 -nworst 1 -nosplit -exclude $io -input_pins -nets -capacitance -transition_time -path_type full_clock_expanded }
redirect $dir/rpt/pt_col_${corner}_min.rpt { report_timing -delay_type min -max_paths 5 -nosplit -exclude $io -path_type full_clock_expanded -input_pins }
redirect -variable lat { report_clock_timing -type latency -nworst 1 -nosplit }
puts $fh "clock_latency_worst [string map {"\n" " | "} [string range [regsub -all {\s+} [regsub {^.*?-{5,}} $lat ""] " "] 0 300]]"
close $fh
exit
