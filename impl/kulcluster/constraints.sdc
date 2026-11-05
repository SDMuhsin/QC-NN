# Constraints of the KUL cluster top KULCluster_snax_KUL_cluster_wrapper, sourced by DC and PrimeTime as QC_SDC through
# flow/tsmc65/common/lib.tcl (qc_env, ::QC_LIB, ::QC_DRV_*, ::QC_LOAD_PIN come from there / site.tcl).
# One clock clk_i (clu_clk), all ports in that domain (chimera drives the wrapper from its cluster clock and puts
# the CDC outside, in chimera_cluster_adapter).
# Environment: QC_PERIOD (ns), QC_CORNER, QC_IO_PCT (IO delay, % of the period, default 20),
# QC_UNC_SETUP / QC_UNC_HOLD (0.25 / 0.05 ns).
# rst_ni: asynchronous reset, ideal network, not timed.  Quasi-static inputs (hart base id, cluster base address,
# boot address; constants in chimera) are not timed either.
set period [qc_env QC_PERIOD]
set corner [qc_env QC_CORNER ss]
set lib    $::QC_LIB($corner)
set io_pct [qc_env QC_IO_PCT 20]

create_clock -name clu_clk -period $period [get_ports clk_i]
set_clock_uncertainty -setup [qc_env QC_UNC_SETUP 0.25] [get_clocks clu_clk]
set_clock_uncertainty -hold  [qc_env QC_UNC_HOLD 0.05]  [get_clocks clu_clk]
set_clock_transition 0.15 [get_clocks clu_clk]
set_driving_cell -lib_cell [lindex $::QC_DRV_CLK 0] -library $lib -pin [lindex $::QC_DRV_CLK 1] [get_ports clk_i]

# ---- reset and quasi-static configuration inputs
set_ideal_network -no_propagate [get_ports rst_ni]
set_false_path -from [get_ports rst_ni]
set_false_path -from [get_ports {hart_base_id_i* cluster_base_addr_i* boot_addr_i*}]

# ---- IO: AXI ports and interrupts, IO delay io_pct % of the period
set data_in [remove_from_collection [all_inputs] [get_ports {clk_i rst_ni}]]
set_input_delay  [expr {$period * $io_pct / 100.0}] -clock clu_clk $data_in
set_output_delay [expr {$period * $io_pct / 100.0}] -clock clu_clk [all_outputs]
set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $lib -pin [lindex $::QC_DRV_IN 1] $data_in
set_load [expr {4.0 * [load_of $lib/$::QC_LOAD_PIN]}] [all_outputs]

# ---- design rules
set_max_transition [expr {min(0.5, 0.1 * $period)}] [current_design]
set_max_fanout 16 [current_design]
