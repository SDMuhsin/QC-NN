# PrimeTime ETM of a routed hard block (column, act) at one corner (results/r5a.md, r45.md): routed netlist + def2spef SPEF,
# propagated clock, inputs without driving cell, output load limit (signoff/pt/common.tcl qb_etm_context), extract_model -library_cell
# -> <run>/out/etm/<top>_<c>.lib/.db + its netlist reference <top>_<c>_ref.txt (qb_etm_ref, read by etmcheck.py)
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
# Crosstalk of the aggressors at the ports kept in the model (R111): with PrimeTime's default false extract_model warns
# MEXT-80 and leaves them out.  [M] rgr rg5cf6581a ss, true vs default: every setup / hold table and every clock -> out
# delay table changed, constraints by -0.10 .. +0.08 ps, clock -> out delays by -2.6 .. +7.1 ps; transitions and the
# clock pulse width unchanged.  common/block.sh blk_post and signoff/verdict.py etm_log fail on that warning (they match
# its message id in parentheses: PrimeTime echoes this comment into the log).
set_app_var si_filter_keep_all_port_aggressors true
extract_model -library_cell -output $dir/out/etm/${top}_$corner -format {lib db}
qb_etm_ref $dir/out/etm/${top}_${corner}_ref.txt
puts "QB_ETM_DONE $corner"
exit
