# R43 opt-in QB43_AUTOL 1 for impl/r5b/pt_chip.tcl (results/r43.md, defect 6): the chip IO delays are shifted by the
# clock latency L of the top registers (inputs 0.2 P + L, outputs 0.2 P - L, impl/r35/pt_top_sdc.tcl).  L was a
# hand-copied number (7.7 for r39_v; measured p50 4.54 tt / 7.63 ss).  Here L = p50 of the propagated clock arrival
# at the top registers' clock pins (blocks / macros excluded, as pt39x R39LAT) of THIS corner, measured after
# update_timing; the IO delays are re-applied with it and timing updated again.
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
    if {[qc_env QB36_RSTFP 1]} { set_false_path -from [get_ports rst_n] }
    set ::env(QB35_TOPL) [format %.3f $_L]
    update_timing
    puts "R43_AUTOL corner $corner top_reg_clk_pins [llength $_v] p50 L [format %.3f $_L] (IO delays re-applied)"
}
