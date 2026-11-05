// tc_sram overlay test: overlay + macro models ($QC_MC_OUT from flow/tsmc65/site/sram.sh) + testbench
../tc_sram.sv
$QC_MC_OUT/qc_sp_1024x64m8/qc_sp_1024x64m8.v
$QC_MC_OUT/qc_rf_16x128m1/qc_rf_16x128m1.v
tb_tc_sram.sv
