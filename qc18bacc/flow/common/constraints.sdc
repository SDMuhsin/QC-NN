# Constraints of the qc18bacc microblocks (qb_pe_*, qb_lane_*), sourced by DC and PrimeTime as QC_SDC through
# flow/tsmc65/common/lib.tcl.  Same rules as qc18acc/impl/constraints.sdc: one clock (qb_clk on port clk), setup /
# hold uncertainty QC_UNC_SETUP / QC_UNC_HOLD, clock transition 0.15 ns, IO delay QC_IO_PCT % of the period (values:
# common/limits.txt through common/limits.tcl qb_limit, R99), rst_n synchronous and quasi-static (false path, buffered
# normally), max transition min(QC_MAX_TRAN, QC_MAX_TRAN_PCT % of P) (qb_max_tran), max fanout 16.
set period [qc_env QC_PERIOD]
set corner [qc_env QC_CORNER ss]
set lib    $::QC_LIB($corner)
source [file join [file dirname [file normalize [info script]]] limits.tcl]

create_clock -name qb_clk -period $period [get_ports clk]
set_clock_uncertainty -setup [qb_limit QC_UNC_SETUP] [get_clocks qb_clk]
set_clock_uncertainty -hold  [qb_limit QC_UNC_HOLD]  [get_clocks qb_clk]
set_clock_transition 0.15 [get_clocks qb_clk]
set_driving_cell -lib_cell [lindex $::QC_DRV_CLK 0] -library $lib -pin [lindex $::QC_DRV_CLK 1] [get_ports clk]

set_false_path -from [get_ports rst_n]
# the deliberate untimed inputs (no input delay: the false path above), declared for the PrimeTime coverage gate
# unclocked_inputs (signoff/pt/common.tcl qb_pt_unclocked_inputs, R109)
set ::QB_UNTIMED_INPUTS {rst_n}

set data_in [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay  [qb_io_delay $period] -clock qb_clk $data_in
set_output_delay [qb_io_delay $period] -clock qb_clk [all_outputs]
set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $lib -pin [lindex $::QC_DRV_IN 1] [get_ports rst_n]
set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $lib -pin [lindex $::QC_DRV_IN 1] $data_in
set_load [expr {4.0 * [load_of $lib/$::QC_LOAD_PIN]}] [all_outputs]

set_max_transition [qb_max_tran $period] [current_design]
# max fanout: a synthesis guideline (DC), not a sign-off criterion (R92, PI decision) - ICC2 ignores it (init.log
# CSTR-011), PrimeTime does not report it, and nothing in P&R or sign-off enforces it
set_max_fanout 16 [current_design]
