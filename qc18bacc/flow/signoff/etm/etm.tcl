# PrimeTime ETM of a routed hard block (column, act) at one corner (results/r5a.md, r45.md): routed netlist + def2spef SPEF,
# propagated clock, inputs without driving cell, output load limit (signoff/pt/common.tcl qb_etm_context), extract_model -library_cell
# -> <run>/out/etm/<top>_<c>.lib/.db
source $::env(QC_FLOW)/common/lib.tcl
set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT); set top $::env(QC_TOP)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner]]
read_verilog $dir/out/$top.v
current_design $top
link_design
qc_apply_constraints $corner
set_propagated_clock [all_clocks]
source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/signoff/pt/common.tcl]
qb_etm_context
qb_pt_spef [qb_pt_spef_file $dir $top $corner]
update_timing
file mkdir $dir/out/etm
extract_model -library_cell -output $dir/out/etm/${top}_$corner -format {lib db}
puts "QB_ETM_DONE $corner"
exit
