# PrimeTime: extracted timing model (ETM) of the routed block qb_pe_hb at one corner (results/pnr_pe.md):
# routed netlist + def2spef SPEF, propagated clock, extract_model -library_cell -> <run>/out/etm/qb_pe_hb_<c>.lib / _lib.db
# (OpenROAD's write_timing_model needs read_spef, which stops at def2spef's empty D_NETs in this build).
source $::env(QC_FLOW)/common/lib.tcl
set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner]]
read_verilog $dir/out/qb_pe_hb.v
current_design qb_pe_hb
link_design
qc_apply_constraints $corner
set_propagated_clock [all_clocks]
read_parasitics -format spef $dir/out/qb_pe_hb_${corner}_pt.spef
update_timing
report_annotated_parasitics > $dir/rpt/etm_${corner}_annotation.rpt
file mkdir $dir/out/etm
extract_model -library_cell -output $dir/out/etm/qb_pe_hb_$corner -format {lib db}
puts "QB_ETM_DONE $corner"
exit
