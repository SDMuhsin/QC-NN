# QB35_IO_TCL of the block hold / ECO steps (repair/hold_eco.tcl via blocks/act/run.sh hold, blocks/col/run.sh eco;
# results/r35.md, r50.md): clock at the sign-off period QB35_PER and the block's own IO budget (QB_IO_BUDGET of its config,
# qb5_io_apply) at the PT sign-off insertion delay QB35_IOL (the db SDC carries the P&R period and the post-CTS L).
# Was repair/act_hold_io.tcl (act only).
set _p $::env(QB35_PER)
create_clock -name qb_clk -period $_p -waveform [list 0 [expr {$_p / 2.0}]] [get_ports clk]
set_clock_uncertainty -setup 0.25 [get_clocks qb_clk]; set_clock_uncertainty -hold 0.05 [get_clocks qb_clk]
set_propagated_clock [all_clocks]
source $::env(QB_IO_BUDGET)
qb5_io_apply $_p $::env(QB35_IOL)
puts "R35_HOLD clock $_p IO budget [file tail $::env(QB_IO_BUDGET)] at L $::env(QB35_IOL)"
