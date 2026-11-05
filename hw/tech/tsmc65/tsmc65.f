// TSMC 65 nm overlay of the tech_cells_generic cells (tc_sram, tc_sram_impl, tc_clk_*).  Use it instead of the
// generic tc_sram.sv / tc_sram_impl.sv / tc_clk.sv (bender targets `asic` / `synthesis` leave those out).
// Synthesis links the macros from their .db (black boxes); simulation needs the macro models
// ($QC_MC_OUT/<instance>/<instance>.v) and, for the clock cells, the standard-cell models.
tc_clk.sv
tc_sram.sv
tc_sram_impl.sv
