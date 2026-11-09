# Constraints of QC18-ACC (top qa_top), sourced by DC and PrimeTime as QC_SDC through flow/tsmc65/common/lib.tcl
# (qc_env, ::QC_LIB, ::QC_DRV_*, ::QC_LOAD_PIN from there / site.tcl).  Same rules as impl/kulcluster/constraints.sdc.
# One clock clk (qa_clk).  Environment: QC_PERIOD (ns), QC_CORNER, QC_IO_PCT (host-port IO delay, % of the period,
# default 20), QC_UNC_SETUP / QC_UNC_HOLD (0.25 / 0.05 ns).
# rst_n: SYNCHRONOUS active-low reset of every control register.  It is a quasi-static input (asserted for several
# cycles from a reset synchroniser of the SoC), so it is not timed (false path) but it is buffered normally (no ideal
# network: DC builds and sizes the fan-out tree, which then shows up in area / power).
set period [qc_env QC_PERIOD]
set corner [qc_env QC_CORNER ss]
set lib    $::QC_LIB($corner)
set io_pct [qc_env QC_IO_PCT 20]

create_clock -name qa_clk -period $period [get_ports clk]
set_clock_uncertainty -setup [qc_env QC_UNC_SETUP 0.25] [get_clocks qa_clk]
set_clock_uncertainty -hold  [qc_env QC_UNC_HOLD 0.05]  [get_clocks qa_clk]
set_clock_transition 0.15 [get_clocks qa_clk]
set_driving_cell -lib_cell [lindex $::QC_DRV_CLK 0] -library $lib -pin [lindex $::QC_DRV_CLK 1] [get_ports clk]

# ---- reset
set_false_path -from [get_ports rst_n]

# ---- host port (32-b request / read-data, busy / done), IO delay io_pct % of the period
set data_in [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay  [expr {$period * $io_pct / 100.0}] -clock qa_clk $data_in
set_output_delay [expr {$period * $io_pct / 100.0}] -clock qa_clk [all_outputs]
set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $lib -pin [lindex $::QC_DRV_IN 1] [get_ports rst_n]
set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $lib -pin [lindex $::QC_DRV_IN 1] $data_in
set_load [expr {4.0 * [load_of $lib/$::QC_LOAD_PIN]}] [all_outputs]

# ---- design rules
set_max_transition [expr {min(0.5, 0.1 * $period)}] [current_design]
set_max_fanout 16 [current_design]
