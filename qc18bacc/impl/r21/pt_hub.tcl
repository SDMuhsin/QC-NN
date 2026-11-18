# R21 PrimeTime sign-off of the routed hub qb_hub at one corner (run.sh post / abs), as impl/r7c/pt_blk.tcl:
# routed netlist + def2spef SPEF + macro .db (syn run.env QC_EXTRA_DB_*), propagated clock, the hub SDC of the run
# (impl/r9b/sdc.py: per-class IO budget, regenerated at QB_PT_PERIOD) shifted by the measured insertion delay L
# (mean of max launch / min capture latency, as the act / column sign-off).  QB21_ETM 1: extract_model instead.
set t0 [clock seconds]
source $::env(QC_FLOW)/common/lib.tcl
set top $::env(QC_TOP); set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs $corner]]
set_app_var read_parasitics_load_locations true
read_verilog [qc_env QB21_V $dir/out/$top.v]
current_design $top
link_design
source $::env(QB21_SDC)
set per [qc_env QB_PT_PERIOD 2.30]
create_clock -name qb_clk -period $per -waveform [list 0 [expr {$per / 2.0}]] [get_ports clk]
set_clock_uncertainty -setup 0.25 [get_clocks qb_clk]; set_clock_uncertainty -hold 0.05 [get_clocks qb_clk]
set_clock_transition 0.15 [get_clocks qb_clk]
set_propagated_clock [all_clocks]
if {[file exists $dir/out/${top}_${corner}_pt.spef]} { read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef } else { puts "R21 no SPEF (dry run)" }
update_timing
redirect -variable cs { report_clock_timing -type summary -clock qb_clk -nosplit }
set lat {}
foreach k {{Maximum setup launch latency} {Minimum setup capture latency}} {
    if {[regexp "$k:\\s*\\n\\s*\\S+\\s+(\[-0-9.\]+)" $cs -> v]} { lappend lat $v }
}
set Lm [expr {[llength $lat] ? ([tcl::mathfunc::max {*}$lat] + [tcl::mathfunc::min {*}$lat]) / 2.0 : 0}]
# R21: the IO budget shift is the P&R value QB_IO_LAT (= the measured p50 hub clock-pin latency after CTS, clk_lat.tcl), not
# the (max + min) / 2 of the act sign-off: the hub's few late ICG subtrees (max 1.95 vs p90 1.35) would move it by 0.25 ns
set L [qc_env QB_IO_LAT $Lm]
qb9_io_apply $per $L
update_timing
if {[qc_env QB21_ETM 0]} {
    file mkdir $dir/out/etm
    extract_model -library_cell -output $dir/out/etm/${top}_$corner -format {lib db}
    puts "QB21_ETM_DONE $corner L $L"
    exit
}
set fh [open $dir/pt_hub_$corner.txt w]
redirect -variable ann { report_annotated_parasitics }
set nets NA
if {[regexp {\n\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|} $ann -> tot rc na]} { set nets "total $tot rc_network $rc not_annotated $na" }
puts $fh "design $top corner $corner period $per lib $::QC_LIB($corner) spef_nets $nets"
puts $fh [format "io_shift_L_ns %.3f (QB_IO_LAT; PT max launch / min capture latencies %s, mid %.3f)" $L $lat $Lm]
set io [add_to_collection [all_inputs] [all_outputs]]
proc fl {fh k p per {fmax 0}} {
    if {![sizeof_collection $p]} { puts $fh "$k none"; return }
    set s [get_attribute $p slack]
    set x [expr {$fmax ? [format " fmax_mhz %.1f" [expr {1000.0 / ($per - $s)}]] : ""}]
    puts $fh [format "%s slack_ns %.3f%s arrival %.3f path %s -> %s" $k $s $x [get_attribute $p arrival] \
        [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
}
fl $fh reg2reg  [get_timing_paths -delay_type max -max_paths 1 -exclude $io] $per 1
fl $fh in2reg   [get_timing_paths -delay_type max -max_paths 1 -from [all_inputs]] $per
fl $fh reg2out  [get_timing_paths -delay_type max -max_paths 1 -to [all_outputs]] $per
fl $fh all      [get_timing_paths -delay_type max -max_paths 1] $per 1
foreach k [lsort [array names ::QB9_IO]] {
    set ps [get_ports -quiet $::QB9_IO($k)]
    if {![sizeof_collection $ps]} continue
    if {[get_attribute [index_collection $ps 0] direction] eq "in"} { fl $fh "  class $k (in)" [get_timing_paths -delay_type max -max_paths 1 -from $ps] $per } else { fl $fh "  class $k (out)" [get_timing_paths -delay_type max -max_paths 1 -to $ps] $per }
}
fl $fh hold_reg2reg [get_timing_paths -delay_type min -max_paths 1 -exclude $io] $per
fl $fh hold_in2reg  [get_timing_paths -delay_type min -max_paths 1 -from [all_inputs]] $per
fl $fh hold_reg2out [get_timing_paths -delay_type min -max_paths 1 -to [all_outputs]] $per
redirect -variable hv { report_constraint -min_delay -all_violators -nosplit }
puts $fh "hold_violating_endpoints [regexp -all -line {VIOLATED} $hv]"
redirect -variable sv { report_constraint -max_delay -all_violators -nosplit }
puts $fh "setup_violating_endpoints [regexp -all -line {VIOLATED} $sv]"
redirect -variable dv { report_constraint -max_transition -max_capacitance -all_violators -nosplit }
puts $fh "drv_violations (SDC max_transition [get_attribute [current_design] max_transition]) [regexp -all -line {VIOLATED} $dv]"
# R21 max-transition question: violators at the library default (tt 0.3852 / ss 0.5596 ns) and at the P&R limit 0.4
foreach mt [list [expr {$corner eq "ss" ? 0.5596 : ($corner eq "ff" ? 0.3852 : 0.3852)}] 0.4] {
    set_max_transition $mt [current_design]
    redirect -variable dv { report_constraint -max_transition -all_violators -nosplit }
    puts $fh "max_transition_violations at $mt ns: [regexp -all -line {VIOLATED} $dv]"
}
file mkdir $dir/rpt
redirect $dir/rpt/pt_hub_${corner}_r2r.rpt { report_timing -max_paths 5 -nosplit -exclude $io -input_pins -nets -capacitance -transition_time }
redirect $dir/rpt/pt_hub_${corner}_end.rpt { report_timing -max_paths 300 -nworst 1 -path_type end -nosplit }
redirect $dir/rpt/pt_hub_${corner}_io.rpt { report_timing -max_paths 3 -nosplit -input_pins -nets -from [all_inputs]; report_timing -max_paths 3 -nosplit -input_pins -nets -to [all_outputs] }
redirect $dir/rpt/pt_hub_${corner}_min.rpt { report_timing -delay_type min -max_paths 5 -nosplit -path_type full_clock_expanded -input_pins }
redirect $dir/rpt/pt_hub_${corner}_clk.rpt { report_clock_timing -type summary -clock qb_clk -nosplit; report_clock_timing -type skew -nworst 3 -nosplit }
redirect $dir/rpt/pt_hub_${corner}_drv.rpt { report_constraint -max_transition -max_capacitance -all_violators -nosplit }
puts $fh "pt_wall_s [expr {[clock seconds] - $t0}]"
close $fh
exit
