# PrimeTime sign-off of the routed column block qb_col_blk at one corner (results/r5a.md): routed netlist + def2spef
# SPEF, propagated clock, IO budget of blocks/col/io_budget.tcl shifted by the block's p50 late / early clock arrival per
# corner (top-level flops balanced with the block's sinks).  Reports per class: reg2reg, act -> reg, act -> act_o (feedthrough), north in -> reg,
# south in -> reg, reg -> south out, hold, DRV, noise / min pulse width / min period (signoff/pt/common.tcl qb_pt_si_checks).  fmax = 1 / (period - WNS) of reg2reg.
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
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/blocks/col/io_budget.tcl]
# (with the act driving cell QB5_FT, replaced by the measured act transition below, R71)
qb5_io_apply $per $L $Le $Tq
# feedthroughs: each act_o driven by one QB5_FT cell (error otherwise), cells and act_o nets dont_touch as in ICC2 init
# (the DMSA ECO neither resizes nor re-buffers them)
set_dont_touch [qb5_ft_cells] true
set_dont_touch [get_nets -of_objects [get_ports {act_o[*]}]] true
# act_o load = this block's own act[b] net (next column's act pin), per bit, on the routed SPEF
qb5_act_o_load [qb5_act_o_caps {apply {p {get_attribute [get_nets -of_objects $p] total_capacitance_max}}}]
update_timing
# act[b] input transition = own act_o[b] transition, iterated to a fixed point (io_budget.tcl qb5_act_tran_fix, R71)
set ::QB5_TRAN_RES [qb5_act_tran_fix]
# the block's noise-only analysis state (R92, PI decision): "<command>" enters it, "<command> off" returns to the timing
# state set up above; the sign-off enters it last (below), the ECO around its noise passes (signoff/pt/drv_eco.tcl)
set ::QB_PT_NOISE_STATE qb5_act_noise_driver
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
puts $fh [format "lib_tcq_ns %.4f min_input_delay_ns %.4f act_min_input_delay_ns %.4f (+ QC_ACT_HOLD_HUB)" $Tq [qb5_hold_min $Le $Tq] [qb5_act_in_min $Le $Tq]]
puts $fh [qb_dont_use_gate post_$corner 0]
puts $fh [format "act_input_transition own act_o transition per bit, fixed-point residual %.5f ns" $::QB5_TRAN_RES]
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
set N [get_ports {cd[*] ctl[*] t2[*]}]
set S [get_ports {pf[*] pw[*] p_ld w_ld s_rd[*] w_r[*] f_vld f_src f_sh w_vld w_sh}]
set SO [get_ports {f_y[*] f_b[*] w_y[*] w_b[*] f_vld_o w_vld_o b2[*] b2_vld}]
fl $fh reg2reg      [get_timing_paths -delay_type max -max_paths 1 -exclude $io] $per 1
fl $fh act2reg      [get_timing_paths -delay_type max -max_paths 1 -from [get_ports {act[*]}] -to $regs] $per
fl $fh act2act_o    [get_timing_paths -delay_type max -max_paths 1 -from [get_ports {act[*]}] -to [get_ports {act_o[*]}]] $per
fl $fh north2reg    [get_timing_paths -delay_type max -max_paths 1 -from $N] $per
fl $fh south2reg    [get_timing_paths -delay_type max -max_paths 1 -from $S] $per
fl $fh reg2south    [get_timing_paths -delay_type max -max_paths 1 -to $SO] $per
fl $fh all          [get_timing_paths -delay_type max -max_paths 1] $per 1
fl $fh hold_reg2reg [get_timing_paths -delay_type min -max_paths 1 -exclude $io] $per
fl $fh hold_in2reg  [get_timing_paths -delay_type min -max_paths 1 -from [all_inputs] -to $regs] $per
fl $fh hold_act2act_o [get_timing_paths -delay_type min -max_paths 1 -from [get_ports {act[*]}] -to [get_ports {act_o[*]}]] $per
# feedthrough delay act -> act_o (no IO delays): max / min over the 4608 bits
set ft [get_timing_paths -delay_type max -max_paths 1 -from [get_ports {act[*]}] -to [get_ports {act_o[*]}]]
set ftn [get_timing_paths -delay_type min -max_paths 1 -from [get_ports {act[*]}] -to [get_ports {act_o[*]}]]
set ain [expr {0.55 * $per + $L}]; set ainm [qb5_act_in_min $Le $Tq]
if {[sizeof_collection $ft]} { puts $fh [format "feedthrough_delay_ns max %.3f min %.3f (budget %.3f = 0.07 P)" \
    [expr {[get_attribute $ft arrival] - $ain}] [expr {[get_attribute $ftn arrival] - $ainm}] [expr {0.07 * $per}]] }
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
qb_pt_paths ${r}_ft.rpt [list -max_paths 3 -from [get_ports {act[*]}] -to [get_ports {act_o[*]}] {*}$pd] \
    [list -delay_type min -max_paths 3 -from [get_ports {act[*]}] -to [get_ports {act_o[*]}] {*}$pd]
qb_pt_paths ${r}_min.rpt [list -delay_type min -max_paths 3 -path_type full_clock_expanded -input_pins]
redirect $dir/rpt/pt_blk_${corner}_clk.rpt { report_clock_timing -type summary -clock qb_clk -nosplit; report_clock_timing -type skew -nworst 3 -nosplit }
redirect $dir/rpt/pt_blk_${corner}_drv.rpt { report_constraint -max_transition -max_capacitance -all_violators -nosplit }
# LAST (R92): the clock pulse checks, then noise on the block's noise state (act driven by QB5_FT; the session stays in
# it, so no timing result may follow), and the act load pins as their own line and gate
qb_pt_si_checks $fh $r $::QB_PT_NOISE_STATE
lassign [qb_pt_noise_pins [get_pins -leaf -of_objects [get_nets -of_objects [get_ports {act[*]}]] -filter "direction==in"]] an at
puts $fh "act_noise $at"
puts "QB_PT_SIGNOFF act_noise $an"
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
