# R11 top SDC (impl/r11/top.cfg), period QB11_PER [1.85 ns].  Blocks: column ETM / hub + act budget liberty
# (impl/r11/blk_lib.py) carry their interface timing; chip IOs 0.2 P (as impl/hard/sdc_pnr.tcl rescaling).
set _p [expr {[info exists ::env(QB11_PER)] ? $::env(QB11_PER) : 1.85}]
create_clock -name qb_clk -period $_p -waveform [list 0 [expr {$_p / 2.0}]] [get_ports clk]
set_clock_uncertainty -setup 0.25 [get_clocks qb_clk]
set_clock_uncertainty -hold 0.05 [get_clocks qb_clk]
set_clock_transition 0.15 [get_clocks qb_clk]
set_max_transition [expr {min(0.5, 0.1 * $_p)}] [current_design]
set_max_fanout [expr {[info exists ::env(QB11_MAXFO)] ? $::env(QB11_MAXFO) : 16}] [current_design]
set _in [lsearch -all -inline -not -exact [all_inputs] [get_ports clk]]
set_input_delay [expr {0.2 * $_p}] -clock qb_clk $_in
set_output_delay [expr {0.2 * $_p}] -clock qb_clk [all_outputs]
set_driving_cell -lib_cell BUFFD4 -pin Z $_in
set_load 0.010 [all_outputs]
# ARM macros: EMA* = 0 / RETN = 1 (impl/r9b/sdc.py: else STA takes the uncharacterised EMA = 100 arc)
set _e [get_pins -quiet -hierarchical */EMA*]
if {[llength $_e]} { set_case_analysis 0 $_e }
set _r [get_pins -quiet -hierarchical */RETN]
if {[llength $_r]} { set_case_analysis 1 $_r }
