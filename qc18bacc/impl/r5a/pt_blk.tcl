# PrimeTime sign-off of the routed column block qb_col_blk at one corner (results/r5a.md): routed netlist + def2spef
# SPEF, propagated clock, IO budget of budget.tcl shifted by the block insertion delay L (top-level flops balanced with
# the block's sinks).  Reports per class: reg2reg, act -> reg, act -> act_o (feedthrough), north in -> reg,
# south in -> reg, reg -> south out, hold.  fmax = 1 / (period - WNS) of reg2reg.
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
set per [get_attribute [get_clocks qb_clk] period]
# insertion delay: mean of the earliest and latest register clock-pin latency
redirect -variable cs { report_clock_timing -type summary -clock qb_clk -nosplit }
set lat {}
foreach k {{Maximum setup launch latency} {Minimum setup capture latency}} {
    if {[regexp "$k:\\s*\\n\\s*\\S+\\s+(\[-0-9.\]+)" $cs -> v]} { lappend lat $v }
}
set L [expr {[llength $lat] ? ([tcl::mathfunc::max {*}$lat] + [tcl::mathfunc::min {*}$lat]) / 2.0 : 0.6}]
source [file dirname [info script]]/budget.tcl
qb5_io_apply $per $L
update_timing
file mkdir $dir/rpt
set fh [open $dir/pt_blk_$corner.txt w]
redirect -variable ann { report_annotated_parasitics }
set nets NA
if {[regexp {\n\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|} $ann -> tot rc na]} { set nets "total $tot rc_network $rc not_annotated $na" }
puts $fh "design $top corner $corner period $per lib $::QC_LIB($corner) spef_nets $nets"
puts $fh [format "insertion_delay_L_ns %.3f (latencies %s)" $L $lat]
set regs [all_registers -data_pins]; set regc [all_registers -clock_pins]
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
set ain [expr {0.55 * $per + $L}]; set ainm [expr {0.05 * $per + $L}]
if {[sizeof_collection $ft]} { puts $fh [format "feedthrough_delay_ns max %.3f min %.3f (budget %.3f = 0.07 P)" \
    [expr {[get_attribute $ft arrival] - $ain}] [expr {[get_attribute $ftn arrival] - $ainm}] [expr {0.07 * $per}]] }
redirect -variable hv { report_constraint -min_delay -all_violators -nosplit }
puts $fh "hold_violating_endpoints [regexp -all -line {VIOLATED} $hv]"
redirect -variable sv { report_constraint -max_delay -all_violators -nosplit }
puts $fh "setup_violating_endpoints [regexp -all -line {VIOLATED} $sv]"
redirect $dir/rpt/pt_blk_${corner}_reg2reg.rpt { report_timing -max_paths 5 -nosplit -exclude $io -input_pins -nets -capacitance -transition_time }
redirect $dir/rpt/pt_blk_${corner}_io.rpt { report_timing -max_paths 2 -nosplit -input_pins -nets -capacitance -transition_time -from [all_inputs]; report_timing -max_paths 2 -nosplit -input_pins -to [all_outputs] }
redirect $dir/rpt/pt_blk_${corner}_min.rpt { report_timing -delay_type min -max_paths 3 -nosplit -path_type full_clock_expanded -input_pins }
redirect $dir/rpt/pt_blk_${corner}_clk.rpt { report_clock_timing -type summary -clock qb_clk -nosplit; report_clock_timing -type skew -nworst 3 -nosplit }
redirect $dir/rpt/pt_blk_${corner}_drv.rpt { report_constraint -max_transition -max_capacitance -all_violators -nosplit }
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
