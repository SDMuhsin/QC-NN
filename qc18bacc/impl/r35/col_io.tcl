# R35 QB35_IO_TCL for the column (hold35.tcl): impl/r5a/budget.tcl IO budget at the PT sign-off insertion delay QB35_IOL
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r5a/budget.tcl]
qb5_io_apply [get_property [get_clocks qb_clk] period] $::env(QB35_IOL)
puts "R35_HOLD column IO budget re-applied at L $::env(QB35_IOL)"
