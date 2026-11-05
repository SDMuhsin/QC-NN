# PrimeTime vectorless power of the routed Snitch FP cluster at one corner (impl/snitch_cluster/pnr/run.sh pt): routed netlist,
# def2spef SPEF, propagated clocks; activity as impl/snitch_cluster/pt_hook.tcl (toggle 0.1 per cycle, static
# probability 0.5 on the data inputs and as the default), at the synthesis period.
source $::env(QC_FLOW)/common/lib.tcl
set top    $::env(QC_TOP)
set corner $::env(QC_CORNER)
set dir    $::env(QC_PNR_OUT)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs $corner]]
set_app_var power_enable_analysis true
read_verilog $dir/out/$top.v
current_design $top
link_design
qc_apply_constraints $corner
set_propagated_clock [all_clocks]
read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef
set_app_var power_default_toggle_rate 0.1
set_app_var power_default_static_probability 0.5
set_switching_activity -static_probability 0.5 -toggle_rate 0.1 -base_clock clu_clk \
    [remove_from_collection [all_inputs] [get_ports clk_i]]
update_power
file mkdir $dir/rpt
report_power -nosplit                      > $dir/rpt/pt_power_${corner}.rpt
report_power -nosplit -hierarchy -levels 3 > $dir/rpt/pt_power_${corner}_hier.rpt
report_clock_timing -type skew -nosplit    > $dir/rpt/pt_skew_${corner}.rpt
redirect -variable pr { report_power -nosplit }
set fh [open $dir/pt_power_$corner.txt w]
set per [get_attribute [get_clocks clu_clk] period]
if {[regexp -line {^\s*Total Power\s*=\s*(\S+)} $pr -> tp]} { puts $fh "power_total_w $tp (vectorless, toggle 0.1, period $per ns)" }
foreach k {{Net Switching Power} {Cell Internal Power} {Cell Leakage Power}} {
    if {[regexp -line "^\\s*$k\\s*=\\s*(\\S+)" $pr -> v]} { puts $fh "power_[string map {{ } _} [string tolower $k]]_w $v" }
}
close $fh
exit
