# PrimeTime sign-off of the routed act-supply block qb_act2_blk at one corner (results/r7c.md; blocks/act/run.sh post), as
# signoff/pt/col_blk.tcl: routed netlist + def2spef SPEF, propagated clock, IO budget blocks/act/io_budget.tcl (QB7_DIN /
# QB7_AOUT) shifted by the insertion delay L (p50, per corner).
# Classes: reg2reg (fmax), data in (s_q / m_q) -> reg, ctl in -> reg, reg -> act, reg -> ctl out, hold, DRV.
set t0 [clock seconds]
source $::env(QC_FLOW)/common/lib.tcl
set top $::env(QC_TOP); set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT)
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
qb_pt_spef $dir/out/${top}_${corner}_pt.spef
update_timing
set per [get_attribute [get_clocks qb_clk] period]
# insertion delay L of this corner (p50 clock-pin latency, as the P&R)
set L [qb_pt_lat $dir $corner]
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/blocks/act/io_budget.tcl]
qb7_io_apply $per $L
update_timing
# design setup ends here for the PrimeTime ECO (signoff/pt/drv_eco.tcl)
if {[info exists ::QB_PT_SETUP_ONLY]} { return }
set fh [open $dir/pt_blk_$corner.txt w]
set nets [qb_pt_ann]
puts $fh "design $top corner $corner period $per lib $::QC_LIB($corner) spef_nets $nets"
puts $fh [format "insertion_delay_L_ns %.3f (p50 clock-pin latency)" $L]
set regs [all_registers -data_pins]
set io [add_to_collection [all_inputs] [all_outputs]]
proc fl {fh k p per {fmax 0}} {
    if {![sizeof_collection $p]} { puts $fh "$k none"; return }
    set s [get_attribute $p slack]
    set x [expr {$fmax ? [format " fmax_mhz %.1f" [expr {1000.0 / ($per - $s)}]] : ""}]
    puts $fh [format "%s slack_ns %.3f%s arrival %.3f path %s -> %s" $k $s $x [get_attribute $p arrival] \
        [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
}
set DI [get_ports {s_q[*] m_q[*]}]
set CI [remove_from_collection [all_inputs] [add_to_collection $DI [get_ports {clk rst_n}]]]
set AO [get_ports {act[*]}]
set CO [remove_from_collection [all_outputs] $AO]
fl $fh reg2reg      [get_timing_paths -delay_type max -max_paths 1 -exclude $io] $per 1
fl $fh din2reg      [get_timing_paths -delay_type max -max_paths 1 -from $DI] $per
fl $fh cin2reg      [get_timing_paths -delay_type max -max_paths 1 -from $CI] $per
fl $fh reg2act      [get_timing_paths -delay_type max -max_paths 1 -to $AO] $per
fl $fh reg2cout     [get_timing_paths -delay_type max -max_paths 1 -to $CO] $per
fl $fh all          [get_timing_paths -delay_type max -max_paths 1] $per 1
fl $fh hold_reg2reg [get_timing_paths -delay_type min -max_paths 1 -exclude $io] $per
fl $fh hold_in2reg  [get_timing_paths -delay_type min -max_paths 1 -from [all_inputs] -to $regs] $per
fl $fh hold_reg2out [get_timing_paths -delay_type min -max_paths 1 -to [all_outputs]] $per
# act clk->pin delay (no IO budget): max / min over the 4 608 bits, vs the budget QB7_AOUT P
set ap [get_timing_paths -delay_type max -max_paths 1 -to $AO]; set apn [get_timing_paths -delay_type min -max_paths 1 -to $AO]
if {[sizeof_collection $ap]} { puts $fh [format "act_clk2pin_ns max %.3f min %.3f (incl. latency; L %.3f; budget %.3f = %s P)" \
    [get_attribute $ap arrival] [get_attribute $apn arrival] $L [expr {[qb7_env QB7_AOUT 0.10] * $per}] [qb7_env QB7_AOUT 0.10]] }
redirect -variable hv { report_constraint -min_delay -all_violators -nosplit }
puts $fh "hold_violating_endpoints [regexp -all -line {VIOLATED} $hv]"
redirect -variable sv { report_constraint -max_delay -all_violators -nosplit }
puts $fh "setup_violating_endpoints [regexp -all -line {VIOLATED} $sv]"
qb_pt_drv $fh
file mkdir $dir/rpt
qb_pt_si_checks $fh $dir/rpt/pt_blk_${corner}
set r $dir/rpt/pt_blk_$corner
set pd {-input_pins -nets -capacitance -transition_time}
qb_pt_paths ${r}_reg2reg.rpt [list -max_paths 5 -exclude $io {*}$pd]
qb_pt_paths ${r}_r2r20.rpt [list -max_paths 200 -nworst 1 -path_type end -exclude $io]
qb_pt_paths ${r}_io.rpt [list -max_paths 2 -from [all_inputs] {*}$pd] [list -max_paths 2 -to [all_outputs] {*}$pd]
qb_pt_paths ${r}_min.rpt [list -delay_type min -max_paths 3 -path_type full_clock_expanded -input_pins]
redirect $dir/rpt/pt_blk_${corner}_clk.rpt { report_clock_timing -type summary -clock qb_clk -nosplit; report_clock_timing -type skew -nworst 3 -nosplit }
redirect $dir/rpt/pt_blk_${corner}_drv.rpt { report_constraint -max_transition -max_capacitance -all_violators -nosplit }
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
