# PrimeTime ETM of the routed column block qb_col_blk at one corner (as impl/hard/pe_etm.tcl; results/r5a.md):
# routed netlist + def2spef SPEF, propagated clock, extract_model -library_cell -> <run>/out/etm/qb_col_blk_<c>.lib/.db
source $::env(QC_FLOW)/common/lib.tcl
set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT); set top $::env(QC_TOP)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner]]
read_verilog $dir/out/$top.v
current_design $top
link_design
qc_apply_constraints $corner
set_propagated_clock [all_clocks]
read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef
update_timing
file mkdir $dir/out/etm
extract_model -library_cell -output $dir/out/etm/${top}_$corner -format {lib db}
puts "QB_ETM_DONE $corner"
exit
