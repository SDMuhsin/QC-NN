# PrimeTime sign-off of a routed ICC2 hard block at one corner QC_CORNER (common/block.sh BLK_PT: the block's script sets
# its hooks below and sources this file last; signoff/pt/col_blk.tcl the column, rgr_blk.tcl the regression block).
# Routed netlist + fill-aware ICC2 SPEF, propagated clock, the block's IO budget (::QB_BLK_IO_BUDGET, a file with
# blocks/col/io_budget.tcl's procs) shifted by the block's p50 late / early clock arrival per corner (top-level flops
# balanced with the block's sinks).  Reports: reg2reg (fmax = 1 / (period - WNS)), the block's path classes, all, hold,
# DRV, recovery / removal, coverage (signoff/pt/common.tcl), path evidence, then noise / min pulse width / min period
# (qb_pt_si_checks) on the block's noise state.  Gate counts: QB_PT_SIGNOFF lines (common/env.sh qb_pt, signoff/verdict.py).
# Hooks (the block script defines them before sourcing this file):
#   ::QB_BLK_IO_BUDGET     IO budget file (required)
#   ::QB_PT_NOISE_STATE    the block's noise-only analysis state command ("<command>" enters it, "<command> off" leaves
#                          it; qb_pt_si_checks).  Default qb_blk_sdc_noise_state: the timing state is the noise state
#                          (every input port has the SDC's driving cell), so noise_undriven_ports is still counted
#   qb_blk_hook <stage> .. optional; stages, in order:
#     setup                after the IO budget: the block's own design setup (default: update_timing)
#     tcq                  returns a suffix of the lib_tcq_ns line
#     head <fh>            further header lines after the dont_use gate line
#     max <regs>           returns {key {get_timing_paths args} ...}: setup classes reported after reg2reg
#     hold <regs>          the same for hold classes after hold_in2reg
#     lines <fh>           further lines after the hold classes
#     paths <r> <pd>       further path reports (qb_pt_paths) after <r>_io.rpt
#     noise <fh>           after qb_pt_si_checks (the session is in the noise state): further noise lines / gates
# The design setup ends at "setup" for the PrimeTime ECO (signoff/pt/drv_eco.tcl: returns when ::QB_PT_SETUP_ONLY exists).
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
# sign-off timer options (SI on), then the SPEF with its coupling capacitances (qb_pt_spef)
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/signoff/pt/common.tcl]
qb_pt_spef [qb_pt_spef_file $dir $top $corner]
update_timing
set per [get_attribute [get_clocks qb_clk] period]
# IO budget shift of this corner (R77, as ICC2 flow/icc2 qb_io_lat): p50 late (L) / early (Le) register clock arrival,
# min input delay from the library's fastest clock -> Q Tq (blocks/col/io_budget.tcl)
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/common/lib_cells.tcl]
set L [qb_pt_lat $dir $corner]
set Le [lindex [qb_clk_arrival early] 0]
set Tq [qb_lib_tcq $corner]
source $::QB_BLK_IO_BUDGET
qb5_io_apply $per $L $Le $Tq
proc qb_blk_has {} { expr {[llength [info procs qb_blk_hook]] > 0} }
if {[qb_blk_has]} { qb_blk_hook setup } else { update_timing }
# the sign-off limits in force (R99; common/limits.tcl): signoff/verdict.py gate limits fails unless = common/limits.txt
puts "QB_PT_LIMITS [qb_limits]"
# the timing state is the noise state (no block hook): the SDC's driving cells hold every input port net
proc qb_blk_sdc_noise_state {{mode on}} {
    return [expr {$mode eq "off" ? "timing state kept (it is the noise state)" : "timing state = noise state (input ports driven by the SDC's driving cells)"}]
}
if {![info exists ::QB_PT_NOISE_STATE]} { set ::QB_PT_NOISE_STATE qb_blk_sdc_noise_state }
# design setup ends here for the PrimeTime ECO (signoff/pt/drv_eco.tcl)
if {[info exists ::QB_PT_SETUP_ONLY]} { return }
file mkdir $dir/rpt
set fh [open $dir/pt_blk_$corner.txt w]
set nets [qb_pt_ann]
puts $fh "design $top corner $corner period $per lib $::QC_LIB($corner) spef_nets $nets"
puts $fh [format "insertion_delay_L_ns %.3f early %.3f (p50 late / early arrival at %d IO-path register clock pins, R85)" $L $Le [sizeof_collection $::QB_IO_REG_CP]]
# R85 before / after record of PI decision 2: the same p50 over all register clock pins (the pre-R85 PT definition), report only
set ar [lmap w {max_rise_arrival min_rise_arrival} { set v [lsort -real [lmap a [get_attribute -quiet [all_registers -clock_pins] $w] { if {![string is double -strict $a]} continue; set a }]]; format %.3f [lindex $v [expr {[llength $v] / 2}]] }]
puts $fh "insertion_delay_all_registers_ns late [lindex $ar 0] early [lindex $ar 1] ([sizeof_collection [all_registers -clock_pins]] clock pins; pre-R85 definition, not applied)"
puts $fh "[format "lib_tcq_ns %.4f min_input_delay_ns %.4f" $Tq [qb5_hold_min $Le $Tq]][expr {[qb_blk_has] ? [qb_blk_hook tcq] : ""}]"
puts $fh [qb_dont_use_gate post_$corner 0]
if {[qb_blk_has]} { qb_blk_hook head $fh }
# register data pins that are endpoints: the tie-constant ones (clock-gate TE, a flop E; qb_pt_coverage counts them) have
# no enabled check arc and were the 228 "invalid end points" PrimeTime warned of at every -to $regs query (R92 [M]; the
# warning id is kept out of this echoed text so that a grep of the log for it finds real ones only)
set regs [filter_collection [all_registers -data_pins] "undefined(case_value)"]
set io [add_to_collection [all_inputs] [all_outputs]]
proc fl {fh k p per {fmax 0}} {
    if {![sizeof_collection $p]} { puts $fh "$k none"; return }
    set s [get_attribute $p slack]
    set x [expr {$fmax ? [format " fmax_mhz %.1f" [expr {1000.0 / ($per - $s)}]] : ""}]
    puts $fh [format "%s slack_ns %.3f%s arrival %.3f path %s -> %s" $k $s $x [get_attribute $p arrival] \
        [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
}
fl $fh reg2reg      [get_timing_paths -delay_type max -max_paths 1 -exclude $io] $per 1
if {[qb_blk_has]} { foreach {k a} [qb_blk_hook max $regs] { fl $fh $k [get_timing_paths -delay_type max -max_paths 1 {*}$a] $per } }
fl $fh all          [get_timing_paths -delay_type max -max_paths 1] $per 1
fl $fh hold_reg2reg [get_timing_paths -delay_type min -max_paths 1 -exclude $io] $per
fl $fh hold_in2reg  [get_timing_paths -delay_type min -max_paths 1 -from [all_inputs] -to $regs] $per
if {[qb_blk_has]} {
    foreach {k a} [qb_blk_hook hold $regs] { fl $fh $k [get_timing_paths -delay_type min -max_paths 1 {*}$a] $per }
    qb_blk_hook lines $fh
}
redirect -variable hv { report_constraint -min_delay -all_violators -nosplit }
puts $fh "hold_violating_endpoints [regexp -all -line {VIOLATED} $hv]"
redirect -variable sv { report_constraint -max_delay -all_violators -nosplit }
puts $fh "setup_violating_endpoints [regexp -all -line {VIOLATED} $sv]"
set drv [qb_pt_drv $fh]
set as [qb_pt_async $fh]
# R68: setup / hold / DRV violators gate the run too (common/env.sh qb_pt fails on any non-zero QB_PT_SIGNOFF count;
# before, only noise / pulse / period did, so a DRV violator was reported but passed the post step); recovery /
# removal too (signoff/pt/common.tcl qb_pt_async; the clock-gating checks are in setup / hold)
puts "QB_PT_SIGNOFF setup [regexp -all -line {VIOLATED} $sv] hold [regexp -all -line {VIOLATED} $hv] $drv $as"
qb_pt_coverage $fh
# path evidence (worst N per class whatever the slack, signoff/pt/common.tcl qb_pt_paths)
set r $dir/rpt/pt_blk_$corner
set pd {-input_pins -nets -capacitance -transition_time}
qb_pt_paths ${r}_reg2reg.rpt [list -max_paths 5 -exclude $io {*}$pd]
qb_pt_paths ${r}_io.rpt [list -max_paths 2 -from [all_inputs] {*}$pd] [list -max_paths 2 -to [all_outputs] {*}$pd]
if {[qb_blk_has]} { qb_blk_hook paths $r $pd }
qb_pt_paths ${r}_min.rpt [list -delay_type min -max_paths 3 -path_type full_clock_expanded -input_pins]
redirect $dir/rpt/pt_blk_${corner}_clk.rpt { report_clock_timing -type summary -clock qb_clk -nosplit; report_clock_timing -type skew -nworst 3 -nosplit }
redirect $dir/rpt/pt_blk_${corner}_drv.rpt { report_constraint -max_transition -max_capacitance -all_violators -nosplit }
# LAST (R92): the clock pulse checks, then noise on the block's noise state (the session stays in it, so no timing
# result may follow), then the block's own noise lines
qb_pt_si_checks $fh $r $::QB_PT_NOISE_STATE
if {[qb_blk_has]} { qb_blk_hook noise $fh }
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
