# PrimeTime of the routed chip qb_chip at one corner (impl/r5b/run.sh pt; results/r5b.md): routed top netlist + def2spef
# SPEF, the column blocks as their ETMs (block-internal timing = the ETM arcs of the routed R5d block), ARM macro libs,
# chip SDC (impl/r4/constraints.sdc at QC_PERIOD), propagated clock.  fmax = 1 / (period - WNS) per class:
#   reg2reg      every clocked start / end incl. block ETM pins and macros (IO excluded)
#   top2top      top-level flops only (no block / macro pin at either end)
#   top2blk / blk2top / blk2blk   paths ending / starting at a column-block pin
#   mac          paths starting or ending at an ARM macro pin
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
qc_apply_constraints $corner
set_propagated_clock [all_clocks]
read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef
update_timing
# R43 opt-in QB43_AUTOL 1: IO shift L = this corner's measured top-register clock p50 (impl/r43/autol43_pt.tcl)
if {[qc_env QB43_AUTOL 0]} { source [file normalize [file dirname [info script]]/../r43/autol43_pt.tcl] }
file mkdir $dir/rpt
set fh [open $dir/pt_chip_$corner.txt w]
redirect -variable ann { report_annotated_parasitics }
set nets NA
if {[regexp {\n\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|} $ann -> tot rc na]} { set nets "total $tot rc_network $rc not_annotated $na" }
set per [get_attribute [get_clocks qb_clk] period]
puts $fh "design $top corner $corner period $per lib $::QC_LIB($corner) spef_nets $nets"
set io [add_to_collection [all_inputs] [all_outputs]]
set blk [get_cells -hierarchical -filter "ref_name==qb_col_blk"]
set mac [get_cells -hierarchical -filter "ref_name=~qb_*_*x*m*"]
set bp [get_pins -of_objects $blk]
set mp [get_pins -of_objects $mac]
puts $fh "blocks [sizeof_collection $blk] macros [sizeof_collection $mac]"
proc fl {fh k p per} {
    if {![sizeof_collection $p]} { puts $fh "$k none"; return }
    set s [get_attribute $p slack]
    puts $fh [format "%s slack_ns %.3f fmax_mhz %.1f arrival %.3f path %s -> %s" $k $s [expr {1000.0 / ($per - $s)}] \
        [get_attribute $p arrival] [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
}
set bo [filter_collection $bp "direction==out"]; set bi [filter_collection $bp "direction==in"]
set mo [filter_collection $mp "direction==out"]; set mi [filter_collection $mp "direction==in"]
fl $fh reg2reg [get_timing_paths -delay_type max -max_paths 1 -exclude $io] $per
fl $fh top2top [get_timing_paths -delay_type max -max_paths 1 -exclude [add_to_collection [add_to_collection $io $bp] $mp]] $per
fl $fh top2blk [get_timing_paths -delay_type max -max_paths 1 -to $bi -exclude [add_to_collection $io $bo]] $per
fl $fh blk2top [get_timing_paths -delay_type max -max_paths 1 -from [get_cells $blk] -exclude [add_to_collection $io $bi]] $per
fl $fh blk2blk [get_timing_paths -delay_type max -max_paths 1 -from [get_cells $blk] -to $bi] $per
fl $fh mac     [get_timing_paths -delay_type max -max_paths 1 -through [add_to_collection $mo $mi] -exclude $io] $per
fl $fh all     [get_timing_paths -delay_type max -max_paths 1] $per
fl $fh hold_reg2reg [get_timing_paths -delay_type min -max_paths 1 -exclude $io] $per
redirect -variable hv { report_constraint -min_delay -all_violators -nosplit }
puts $fh "hold_violating_endpoints [regexp -all -line {VIOLATED} $hv]"
redirect -variable sv { report_constraint -max_delay -all_violators -nosplit }
puts $fh "setup_violating_endpoints [regexp -all -line {VIOLATED} $sv]"
redirect $dir/rpt/pt_chip_${corner}_reg2reg.rpt { report_timing -max_paths 10 -nosplit -exclude $io -input_pins -nets -capacitance -transition_time }
redirect $dir/rpt/pt_chip_${corner}_min.rpt { report_timing -delay_type min -max_paths 3 -nosplit -exclude $io -path_type full_clock_expanded -input_pins }
redirect $dir/rpt/pt_chip_${corner}_viol.rpt { report_constraint -max_delay -all_violators -nosplit }
redirect -variable lat { report_clock_timing -type summary -clock qb_clk -nosplit }
puts $fh "clock_summary [string map {"\n" " | "} [regsub -all {[ \t]+} $lat " "]]"
# R6b: QB_PT_EXTRA = a Tcl file sourced here (fh, per, io, blk, mac, bp, mp, bi, bo, mi, mo set), e.g. impl/r6b/pt_extra.tcl
if {[info exists ::env(QB_PT_EXTRA)] && $::env(QB_PT_EXTRA) ne ""} { source $::env(QB_PT_EXTRA) }
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
