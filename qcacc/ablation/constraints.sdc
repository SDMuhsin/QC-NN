# Constraints of the standalone ablation cores AblGemm_<variant> (qcacc/ablation), sourced by DC / PT as QC_SDC
# through flow/tsmc65/common/lib.tcl.  Same values as impl/kulcluster/constraints.sdc (the cluster runs kul_w4.2p /
# qc_w4.2): uncertainty 0.25 / 0.05 ns, clock transition 0.15 ns, IO delay QC_IO_PCT (20) % of the period,
# BUFFD4 input drivers, 4 x INVD4 output loads, max transition min(0.5, 0.1 T), max fanout 16.
# reset: asynchronous (Chisel RequireAsyncReset), ideal network, not timed.
set period [qc_env QC_PERIOD]
set corner [qc_env QC_CORNER ss]
set lib    $::QC_LIB($corner)
set io_pct [qc_env QC_IO_PCT 20]

create_clock -name clock -period $period [get_ports clock]
set_clock_uncertainty -setup [qc_env QC_UNC_SETUP 0.25] [get_clocks clock]
set_clock_uncertainty -hold  [qc_env QC_UNC_HOLD 0.05]  [get_clocks clock]
set_clock_transition 0.15 [get_clocks clock]
set_driving_cell -lib_cell [lindex $::QC_DRV_CLK 0] -library $lib -pin [lindex $::QC_DRV_CLK 1] [get_ports clock]

set_ideal_network -no_propagate [get_ports reset]
set_false_path -from [get_ports reset]

set data_in [remove_from_collection [all_inputs] [get_ports {clock reset}]]
set_input_delay  [expr {$period * $io_pct / 100.0}] -clock clock $data_in
set_output_delay [expr {$period * $io_pct / 100.0}] -clock clock [all_outputs]
set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $lib -pin [lindex $::QC_DRV_IN 1] $data_in
set_load [expr {4.0 * [load_of $lib/$::QC_LOAD_PIN]}] [all_outputs]

set_max_transition [expr {min(0.5, 0.1 * $period)}] [current_design]
set_max_fanout 16 [current_design]
