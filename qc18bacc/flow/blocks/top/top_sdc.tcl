# OpenROAD SDC of the chip top qb_chip (P(SDC) of blocks/top/top.cfg; results/r11.md, r35.md, r36.md), period
# QB_TOP_PERIOD.  Blocks: column ETM / hub + act ETMs carry their interface timing; chip IOs 0.2 P shifted by the top
# clock latency QB35_TOPL [0] exactly as PrimeTime does (blocks/top/pt_sdc.tcl: inputs 0.2 P + L, outputs 0.2 P - L).
# The command sequence is kept as the R11 -> R35 -> R36 chain issued it (IO delays set twice, EMA case analysis redone).
set _p $::env(QB_TOP_PERIOD)
create_clock -name qb_clk -period $_p -waveform [list 0 [expr {$_p / 2.0}]] [get_ports clk]
set_clock_uncertainty -setup 0.25 [get_clocks qb_clk]
set_clock_uncertainty -hold 0.05 [get_clocks qb_clk]
set_clock_transition 0.15 [get_clocks qb_clk]
set_max_transition [expr {min(0.5, 0.1 * $_p)}] [current_design]
set_max_fanout 16 [current_design]
set _in [lsearch -all -inline -not -exact [all_inputs] [get_ports clk]]
set_input_delay [expr {0.2 * $_p}] -clock qb_clk $_in
set_output_delay [expr {0.2 * $_p}] -clock qb_clk [all_outputs]
set_driving_cell -lib_cell BUFFD4 -pin Z $_in
set_load 0.010 [all_outputs]
# ARM macros: EMA* = 0 / RETN = 1 (else STA takes the uncharacterised EMA = 100 arc)
set _e [get_pins -quiet -hierarchical */EMA*]
if {[llength $_e]} { set_case_analysis 0 $_e }
set _r [get_pins -quiet -hierarchical */RETN]
if {[llength $_r]} { set_case_analysis 1 $_r }
# R31 EMA fix: OpenSTA's */EMA* also matches the ARM macros' QA outputs, so the case analysis is redone on the EMA /
# EMAA / EMAB bits only
if {[llength $_e]} { unset_case_analysis $_e }
set _e [get_pins -quiet -hierarchical -regexp {.*/EMA[AB]?\[[0-9]+\]}]
if {[llength $_e]} { set_case_analysis 0 $_e }
# R36: chip IO delays shifted by the top clock latency QB35_TOPL (one IO model for P&R and sign-off)
set _L [expr {[info exists ::env(QB35_TOPL)] ? $::env(QB35_TOPL) : 0.0}]
set_input_delay [expr {0.2 * $_p + $_L}] -clock qb_clk $_in
set_output_delay [expr {0.2 * $_p - $_L}] -clock qb_clk [all_outputs]
# the chip reset input is asynchronous (recovery / removal from the pin are not a synchronous budget): false-pathed from
# the port, as in PT (r36_f1 post-CTS: worst setup was rst_n -> seq kq_reg recovery through two hub feedthroughs)
set_false_path -from [get_ports rst_n]
