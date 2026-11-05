# Constraints of the Snitch cluster tops, sourced by DC and PrimeTime as QC_SDC through flow/tsmc65/common/lib.tcl
# (qc_env, ::QC_LIB, ::QC_DRV_*, ::QC_LOAD_PIN come from there / site.tcl).  Two tops:
#   snitch_cluster_wrapper (fp, primary):  one clock clk_i (clu_clk); all ports in that domain
#   qc_snitch_cluster_top (chimera-exact): clu_clk_i (cluster) and soc_clk_i (SoC-side AXI ports, SoC side of the
#     axi_cdc in chimera_cluster_adapter).  Asynchronous clock groups: CDC paths are not timed here (a max-delay
#     check of the gray pointers belongs to the P&R signoff).
# Environment: QC_PERIOD (cluster clock, ns), QC_SOC_PERIOD (SoC clock, default = QC_PERIOD), QC_CORNER,
# QC_IO_PCT (IO delay, % of the clock period, default 20), QC_UNC_SETUP / QC_UNC_HOLD (0.25 / 0.05 ns).
# rst_ni: asynchronous reset, ideal network, not timed (reset tree built in P&R).  Quasi-static configuration inputs
# (hart base id, cluster base address, boot address, SRAM margin config, clk_d2 bypass; constants in chimera) are not
# timed either.
set period     [qc_env QC_PERIOD]
set soc_period [qc_env QC_SOC_PERIOD $period]
set corner     [qc_env QC_CORNER ss]
set lib        $::QC_LIB($corner)
set io_pct     [qc_env QC_IO_PCT 20]

set two_clocks [sizeof_collection [get_ports -quiet soc_clk_i]]
if {$two_clocks} {
    set clk_ports {clu_clk_i soc_clk_i}
    create_clock -name clu_clk -period $period     [get_ports clu_clk_i]
    create_clock -name soc_clk -period $soc_period [get_ports soc_clk_i]
    set_clock_groups -asynchronous -group [get_clocks clu_clk] -group [get_clocks soc_clk]
    set axi_clk soc_clk; set axi_period $soc_period
} else {
    set clk_ports {clk_i}
    create_clock -name clu_clk -period $period [get_ports clk_i]
    set axi_clk clu_clk; set axi_period $period
}
foreach_in_collection c [all_clocks] {
    set_clock_uncertainty -setup [qc_env QC_UNC_SETUP 0.25] $c
    set_clock_uncertainty -hold  [qc_env QC_UNC_HOLD 0.05]  $c
    set_clock_transition 0.15 $c
}
set_driving_cell -lib_cell [lindex $::QC_DRV_CLK 0] -library $lib -pin [lindex $::QC_DRV_CLK 1] [get_ports $clk_ports]

# ---- reset and quasi-static configuration inputs
set_ideal_network -no_propagate [get_ports rst_ni]
set_false_path -from [get_ports rst_ni]
set static_in [get_ports -quiet {hart_base_id_i* cluster_base_addr_i* boot_addr_i* sram_cfgs_i* clk_d2_bypass_i}]
if {[sizeof_collection $static_in]} { set_false_path -from $static_in }

# ---- IO: AXI ports in the AXI clock domain, the other core-side inputs in the cluster domain
set axi_in  [get_ports -quiet {narrow_in_req_i* narrow_out_resp_i* wide_out_resp_i* wide_in_req_i*}]
set axi_out [get_ports -quiet {narrow_in_resp_o* narrow_out_req_o* wide_out_req_o* wide_in_resp_o*}]
set clu_in  [get_ports -quiet {debug_req_i* meip_i* mtip_i* msip_i* widemem_bypass_i}]
set_input_delay  [expr {$axi_period * $io_pct / 100.0}] -clock $axi_clk $axi_in
set_output_delay [expr {$axi_period * $io_pct / 100.0}] -clock $axi_clk $axi_out
set_input_delay  [expr {$period * $io_pct / 100.0}]     -clock clu_clk  $clu_in
set data_in [remove_from_collection [all_inputs] [get_ports [concat $clk_ports rst_ni]]]
set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $lib -pin [lindex $::QC_DRV_IN 1] $data_in
set_load [expr {4.0 * [load_of $lib/$::QC_LOAD_PIN]}] [all_outputs]

# ---- design rules
set_max_transition [expr {min(0.5, 0.1 * $period)}] [current_design]
set_max_fanout 16 [current_design]
