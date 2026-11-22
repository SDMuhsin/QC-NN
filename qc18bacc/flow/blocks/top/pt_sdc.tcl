# PrimeTime SDC of the routed chip top qb_chip (QC_SDC of signoff/pt/top_chip.tcl; results/r35.md, r36.md): the
# OpenROAD top SDC (blocks/top/top_sdc.tcl) in PT syntax with the R31 EMA fix, chip IO delays shifted by the top clock
# latency QB35_TOPL (inputs + L, outputs - L: the chip IOs are timed against the propagated clock at the top flops;
# top_chip.tcl re-applies them with this corner's measured L), and the asynchronous reset port rst_n false-pathed.
set _p [qc_env QC_PERIOD 5.0]; set _L [qc_env QB35_TOPL 0.0]
create_clock -name qb_clk -period $_p -waveform [list 0 [expr {$_p / 2.0}]] [get_ports clk]
set_clock_uncertainty -setup 0.25 [get_clocks qb_clk]
set_clock_uncertainty -hold 0.05 [get_clocks qb_clk]
set_clock_transition 0.15 [get_clocks qb_clk]
set_max_transition [expr {min(0.5, 0.1 * $_p)}] [current_design]
set _in [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay [expr {0.2 * $_p + $_L}] -clock qb_clk $_in
set_output_delay [expr {0.2 * $_p - $_L}] -clock qb_clk [all_outputs]
set_driving_cell -lib_cell BUFFD4 -pin Z $_in
set_load 0.010 [all_outputs]
set _e [get_pins -quiet -hierarchical -regexp {.*/EMA[AB]?\[[0-9]+\]}]
if {[sizeof_collection $_e]} { set_case_analysis 0 $_e }
set _r [get_pins -quiet -hierarchical */RETN]
if {[sizeof_collection $_r]} { set_case_analysis 1 $_r }
set rf2p [get_cells -quiet -hierarchical -filter "is_hierarchical==false && (ref_name==qb_s_256x128m1 || ref_name==qb_b_128x128m1)"]
if {[sizeof_collection $rf2p]} { set_false_path -to [filter_collection [get_pins -of_objects $rf2p] "lib_pin_name==CLKA || lib_pin_name==CLKB"] }
set_false_path -from [get_ports rst_n]
