# PrimeTime post-route timing of QC18-ACC at one corner (qc18acc/pnr/run.sh pt): flow/tsmc65/pnr/pt_post.tcl (routed
# flat netlist, def2spef SPEF of the corner, design SDC, propagated clock) + fmax lines:
#   all       worst setup path of qa_clk (incl. the host-port IO paths: their input / output delays are relative to
#             the ideal clock edge, so the 1.5-3.5 ns propagated clock latency makes them pessimistic / hold-fixed)
#   reg2reg   worst setup path between clocked cells (registers, macros, ICG enables), IO excluded
#   reg2reg_logic  as reg2reg without the paths from / to a macro pin
# fmax = 1 / (period - WNS).  Environment as pt_post.tcl (QC_PNR_OUT, QC_TOP, QC_CORNER, QC_PERIOD, QC_SDC, ...).
set t0 [clock seconds]
source $::env(QC_FLOW)/common/lib.tcl
set top    $::env(QC_TOP)
set corner $::env(QC_CORNER)
set dir    $::env(QC_PNR_OUT)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs $corner]]
set_app_var read_parasitics_load_locations true
read_verilog $dir/out/$top.v
current_design $top
link_design
# constraints as in sta/pt.tcl (regenerated for this corner's library, or QC_SDC) when the synthesis run.env is
# known, else the SDC written by DC (its driving cells / operating conditions name the synthesis corner)
if {[qc_env QC_PERIOD] ne ""} {
    qc_apply_constraints $corner; set sdc_src [expr {[qc_env QC_SDC] ne "" ? "QC_SDC" : "generated"}]
} else {
    read_sdc $::env(QC_SDC_FILE); set sdc_src dc_sdc
}
set_propagated_clock [all_clocks]
# QA_IO_REF=1: host-port IO delays relative to the propagated clock at the host interface register (io_ref.tcl, as
# the P&R run with P(QA_IO_REF) 1); default: the synthesis SDC (ideal clock edge)
set io_model ideal_edge
if {[qc_env QA_IO_REF 0]} { source $::env(QC_FLOW)/../../qc18acc/pnr/io_ref.tcl; set io_model host_reg_clock }
read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef
update_timing
file mkdir $dir/rpt
report_annotated_parasitics -list_not_annotated -max_nets 20 > $dir/rpt/pt_post_${corner}_annotation.rpt
report_timing -max_paths 10 -nosplit                 > $dir/rpt/pt_post_${corner}_max.rpt
report_timing -delay_type min -max_paths 10 -nosplit > $dir/rpt/pt_post_${corner}_min.rpt
report_constraint -all_violators -nosplit            > $dir/rpt/pt_post_${corner}_violators.rpt
set fh [open $dir/pt_post_$corner.txt w]
redirect -variable ann { report_annotated_parasitics }
set nets NA
if {[regexp {\n\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|} $ann -> tot rc na]} {
    set nets "total $tot rc_network $rc not_annotated $na"
}
puts $fh "design $top corner $corner lib $::QC_LIB($corner) constraints $sdc_src io $io_model spef_nets $nets"
qc_put_timing $fh
set per [get_attribute [get_clocks qa_clk] period]
proc fl {fh k p per} {
    if {![sizeof_collection $p]} { puts $fh "$k none"; return }
    set s [get_attribute $p slack]
    puts $fh [format "%s wns_ns %.3f fmax_mhz %.1f path %s -> %s" $k $s [expr {1000.0 / ($per - $s)}] \
        [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
}
fl $fh all [get_timing_paths -delay_type max -max_paths 1] $per
set io [add_to_collection [all_inputs] [all_outputs]]
fl $fh reg2reg [get_timing_paths -delay_type max -max_paths 1 -exclude $io] $per
fl $fh hold_reg2reg [get_timing_paths -delay_type min -max_paths 1 -exclude $io] $per
# logic only: neither launched by a macro (CLK -> Q) nor ending at a macro input (as power/lowv_sta.tcl)
set mcs [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~qa_*m*"]
if {[sizeof_collection $mcs]} {
    set mpins [add_to_collection [get_pins -of $mcs -filter "direction==out"] [get_pins -of $mcs -filter "direction==in"]]
    fl $fh reg2reg_logic [get_timing_paths -delay_type max -max_paths 1 -exclude [add_to_collection $io $mpins]] $per
}
redirect $dir/rpt/pt_post_${corner}_reg2reg.rpt { report_timing -max_paths 5 -nosplit -exclude $io -path_type full_clock_expanded }
redirect $dir/rpt/pt_post_${corner}_min_clk.rpt { report_timing -delay_type min -max_paths 3 -nosplit -path_type full_clock_expanded -input_pins -nets -capacitance -transition_time }
redirect $dir/rpt/pt_post_${corner}_skew.rpt { report_clock_timing -type skew -nworst 5 -nosplit }
redirect -variable lat { report_clock_timing -type latency -nworst 1 -nosplit }
puts $fh "clock_latency_worst [string map {"\n" " | "} [string range [regsub -all {\s+} [regsub {^.*?-{5,}} $lat ""] " "] 0 300]]"
redirect -variable sk { report_clock_timing -type skew -nworst 1 -nosplit }
puts $fh "clock_skew_worst [string map {"\n" " | "} [string range [regsub -all {\s+} [regsub {^.*?-{5,}} $sk ""] " "] 0 300]]"
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
# QA_PT_EXTRA: optional Tcl file of extra reports (diagnosis), sourced with the design timed
if {[qc_env QA_PT_EXTRA] ne ""} { source [qc_env QA_PT_EXTRA] }
exit
