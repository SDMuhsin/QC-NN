# R35 QB35_IO_TCL for the act block (hold35.tcl): clock at the chip period QB35_PER and impl/r7c/budget.tcl IO budget at
# the PT sign-off insertion delay QB35_IOL (the db SDC carries the P&R period 5.0 and QB_IO_LAT 0.77; PT measured 0.99)
set _p $::env(QB35_PER)
create_clock -name qb_clk -period $_p -waveform [list 0 [expr {$_p / 2.0}]] [get_ports clk]
set_clock_uncertainty -setup 0.25 [get_clocks qb_clk]; set_clock_uncertainty -hold 0.05 [get_clocks qb_clk]
set_propagated_clock [all_clocks]
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r7c/budget.tcl]
qb7_io_apply $_p $::env(QB35_IOL)
puts "R35_HOLD act clock $_p IO budget at L $::env(QB35_IOL)"
