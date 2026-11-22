# Constraints of the qc18bacc microblocks (qb_pe_*, qb_lane_*), sourced by DC and PrimeTime as QC_SDC through
# flow/tsmc65/common/lib.tcl.  Same rules as qc18acc/impl/constraints.sdc: one clock (qb_clk on port clk), setup /
# hold uncertainty QC_UNC_SETUP / QC_UNC_HOLD (0.25 / 0.05 ns), clock transition 0.15 ns, IO delay QC_IO_PCT (20) %
# of the period, rst_n synchronous and quasi-static (false path, buffered normally), max transition min(0.5, 0.1 P),
# max fanout 16.
set period [qc_env QC_PERIOD]
set corner [qc_env QC_CORNER ss]
set lib    $::QC_LIB($corner)
set io_pct [qc_env QC_IO_PCT 20]

create_clock -name qb_clk -period $period [get_ports clk]
set_clock_uncertainty -setup [qc_env QC_UNC_SETUP 0.25] [get_clocks qb_clk]
set_clock_uncertainty -hold  [qc_env QC_UNC_HOLD 0.05]  [get_clocks qb_clk]
set_clock_transition 0.15 [get_clocks qb_clk]
set_driving_cell -lib_cell [lindex $::QC_DRV_CLK 0] -library $lib -pin [lindex $::QC_DRV_CLK 1] [get_ports clk]

set_false_path -from [get_ports rst_n]

set data_in [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay  [expr {$period * $io_pct / 100.0}] -clock qb_clk $data_in
set_output_delay [expr {$period * $io_pct / 100.0}] -clock qb_clk [all_outputs]
set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $lib -pin [lindex $::QC_DRV_IN 1] [get_ports rst_n]
set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $lib -pin [lindex $::QC_DRV_IN 1] $data_in
set_load [expr {4.0 * [load_of $lib/$::QC_LOAD_PIN]}] [all_outputs]

set_max_transition [expr {min(0.5, 0.1 * $period)}] [current_design]
set_max_fanout 16 [current_design]
