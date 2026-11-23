# PrimeTime of the routed chip top qb_chip at one corner (blocks/top/run.sh pt; results/r5b.md, r39.md, r42.md, r43.md):
# routed top netlist + def2spef SPEF, the hard blocks as their ETMs (QC_EXTRA_DB_<C>), ARM macro libs, QC_SDC
# (blocks/top/pt_sdc.tcl) at QC_PERIOD, propagated clock; chip IO latency L measured at this corner (below).
# fmax = 1 / (period - WNS) per class:
#   reg2reg      every clocked start / end incl. block ETM pins and macros (IO excluded)
#   top2top      top-level flops only (no column / hub / act block pin, no macro pin, no chip IO on the path)
#   top2blk / blk2top / blk2blk   paths ending / starting at a column-block pin
#   mac          paths starting or ending at an ARM macro pin
# then the R37 block conditions at chip level, violators and clock latencies (R39), not-annotated nets (R42).
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
# sign-off timer options (SI on), then the SPEF with its coupling capacitances (qb_pt_spef)
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/signoff/pt/common.tcl]
# hard-block ETMs: extract_model bakes the block's OCV derate (common/derate.tcl, sourced by etm.tcl / the block scripts)
# into the ETM arcs (R67 [M], r65 column tt extracted with and without the derate: cell_rise / cell_fall median x1.023,
# setup / hold constraints x1.04, transitions x1.000), so the ETM instances' cell delays are not derated a second time;
# the top nets to their pins and the ARM macros (real libraries) keep the derate
set _etm [get_cells -quiet -hierarchical -filter "ref_name==qb_col_blk || ref_name==qb_hub || ref_name==qb_act2_blk"]
if {[sizeof_collection $_etm]} {
    set_timing_derate -late  -cell_delay 1.0 $_etm
    set_timing_derate -early -cell_delay 1.0 $_etm
    puts "QB_ETM_DERATE [sizeof_collection $_etm] ETM instances at cell derate 1.0 (derate baked into the ETM)"
}
qb_pt_spef $dir/out/${top}_${corner}_pt.spef
update_timing
# IO shift L (results/r43.md defect 6) = p50 of the propagated clock arrival at the top registers' clock pins (blocks /
# macros excluded, as R39LAT below) of THIS corner, measured after update_timing; the IO delays are re-applied with it
# (inputs 0.2 P + L, outputs 0.2 P - L) and timing updated again.
set _b [get_cells -quiet -hierarchical -filter "ref_name==qb_col_blk || ref_name==qb_hub || ref_name==qb_act2_blk || ref_name=~qb_*_*x*m*"]
set _rc [remove_from_collection [all_registers -clock_pins] [get_pins -of_objects $_b]]
set _v {}
foreach_in_collection _p $_rc { set _a [get_attribute -quiet $_p max_rise_arrival]; if {[string is double -strict $_a]} { lappend _v $_a } }
set _v [lsort -real $_v]
if {[llength $_v]} {
    set _L [lindex $_v [expr {int(0.5 * ([llength $_v] - 1))}]]; set _p [get_attribute [get_clocks qb_clk] period]
    set _in [remove_from_collection [all_inputs] [get_ports clk]]
    set_input_delay [expr {0.2 * $_p + $_L}] -clock qb_clk $_in
    set_output_delay [expr {0.2 * $_p - $_L}] -clock qb_clk [all_outputs]
    set_false_path -from [get_ports rst_n]
    set ::env(QB35_TOPL) [format %.3f $_L]
    update_timing
    puts "R43_AUTOL corner $corner top_reg_clk_pins [llength $_v] p50 L [format %.3f $_L] (IO delays re-applied)"
}
file mkdir $dir/rpt
set fh [open $dir/pt_chip_$corner.txt w]
set nets [qb_pt_ann]
set per [get_attribute [get_clocks qb_clk] period]
puts $fh "design $top corner $corner period $per lib $::QC_LIB($corner) spef_nets $nets"
set io [add_to_collection [all_inputs] [all_outputs]]
set blk [get_cells -hierarchical -filter "ref_name==qb_col_blk"]
set mac [get_cells -hierarchical -filter "ref_name=~qb_*_*x*m*"]
set bp [get_pins -of_objects $blk]
set mp [get_pins -of_objects $mac]
# the other hard blocks (hub, act): their pins are not top-to-top either
set hp [get_pins -of_objects [get_cells -hierarchical -filter "ref_name==qb_hub || ref_name==qb_act2_blk"]]
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
fl $fh top2top [get_timing_paths -delay_type max -max_paths 1 -exclude [add_to_collection [add_to_collection [add_to_collection $io $bp] $mp] $hp]] $per
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
# R39 chip sign-off extras (results/r39.md; appended to pt_chip_<corner>.txt; violators -> rpt/r39_<corner>_viol.txt):
#   hub_ft     paths through a hub ETM input pin AND a hub ETM output pin (R37: 47 tt / 97 ss in2out feed-through
#              endpoints were set false in the block PT and must be timed here end to end)
#   hub2act    paths from the hub into the act (s_q / m_q, R37 split hub 0.26 P / act 0.74 P)
#   act2col    paths from the act into the column blocks (R37 act output budget 0.25 P)
#   check_timing: unconstrained endpoints (a cross-block arc missing in an ETM shows up as unconstrained, not violated)
set hub [get_cells -hierarchical -filter "ref_name==qb_hub"]
set act [get_cells -hierarchical -filter "ref_name==qb_act2_blk"]
set hi [get_pins -of_objects $hub -filter "direction==in"]; set ho [get_pins -of_objects $hub -filter "direction==out"]
# R43 (results/r43.md, defect 8): hub_ft = every data path through a hub data input AND a hub output (the hub clk pin
# excluded: clk -> output arcs are launches, not feed-throughs), all slacks counted (get_timing_paths returns only
# violating paths unless -slack_lesser_than is given)
set hi [filter_collection $hi "lib_pin_name!=clk"]; set _ftsl [list -slack_lesser_than 1e9]
set ai [get_pins -of_objects $act -filter "direction==in"]; set ao [get_pins -of_objects $act -filter "direction==out"]
foreach dt {max min} {
    set k [expr {$dt eq "max" ? "" : "hold_"}]
    set ft [get_timing_paths -delay_type $dt -through $hi -through $ho -max_paths 100000 -nworst 1 {*}$_ftsl]
    set nv 0; set ws 1e9
    foreach_in_collection p $ft { set s [get_attribute $p slack]; if {$s < $ws} { set ws $s }; if {$s < 0} { incr nv } }
    puts $fh [format "${k}hub_ft endpoints %d violators %d worst_slack %s" [sizeof_collection $ft] $nv [expr {$ws < 1e8 ? [format %.3f $ws] : "NA"}]]
    fl $fh ${k}hub2act [get_timing_paths -delay_type $dt -max_paths 1 -from $hub -to $ai] $per
    fl $fh ${k}act2col [get_timing_paths -delay_type $dt -max_paths 1 -from $act -to $bi] $per
    fl $fh ${k}io_in   [get_timing_paths -delay_type $dt -max_paths 1 -from [remove_from_collection [all_inputs] [get_ports clk]]] $per
    fl $fh ${k}io_out  [get_timing_paths -delay_type $dt -max_paths 1 -to [all_outputs]] $per
}
redirect -variable ct { check_timing -verbose }
puts $fh "check_timing_unconstrained_endpoints [regexp -all -line {unconstrained} $ct] (see rpt/r39_${corner}_check_timing.rpt)"
set f [open $dir/rpt/r39_${corner}_check_timing.rpt w]; puts $f $ct; close $f
set f [open $dir/rpt/r39_${corner}_viol.txt w]
foreach dt {max min} {
    foreach_in_collection p [get_timing_paths -delay_type $dt -max_paths 100000 -nworst 1 -slack_lesser_than 0] {
        puts $f [format "%s %.3f %s -> %s" [expr {$dt eq "max" ? "setup" : "hold"}] [get_attribute $p slack] \
            [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
    }
}
close $f
# R39LAT: clock arrival at the TOP registers' clock pins (blocks / macros excluded) of this corner: the IO shift L
# (QB36_TOPL) should be this corner's p50 (R37 lesson: ss PT with the tt L mis-models every IO path).
set rc [remove_from_collection [all_registers -clock_pins] [get_pins -of_objects [add_to_collection [add_to_collection [add_to_collection $blk $hub] $act] $mac]]]
set v {}
foreach_in_collection p $rc { set a [get_attribute -quiet $p max_rise_arrival]; if {[string is double -strict $a]} { lappend v $a } }
set v [lsort -real $v]; set n [llength $v]
if {$n} { puts $fh [format "R39LAT %s top_reg_clk_pins %d p10 %.3f p50 %.3f p90 %.3f min %.3f max %.3f (io shift L used %s)" $corner $n \
    [lindex $v [expr {int(0.1 * ($n - 1))}]] [lindex $v [expr {int(0.5 * ($n - 1))}]] [lindex $v [expr {int(0.9 * ($n - 1))}]] [lindex $v 0] [lindex $v end] [qc_env QB35_TOPL 0]] }
foreach c [list $hub $act] { foreach_in_collection q [get_pins -of_objects $c -filter "lib_pin_name==clk"] { puts $fh [format "R39BLKCLK %s %s" [get_object_name $q] [get_attribute -quiet $q max_rise_arrival]] } }
# R42: a sample of the nets PT reports as not annotated
redirect $dir/rpt/r42_${corner}_notann.rpt { report_annotated_parasitics -list_not_annotated -max_nets 3000 }
qb_pt_si_checks $fh $dir/rpt/pt_chip_$corner
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
