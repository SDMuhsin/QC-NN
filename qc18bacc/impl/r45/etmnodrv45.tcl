# R45 test: the column ETM as impl/r5a/etm.tcl, but without the SDC driving cells on the data inputs (constraints.sdc
# set_driving_cell BUFFD4 on every data input; extract_model then varies the BUFFD4 *input* transition to reach its
# index slews: MEXT-81 "driving cell ... insensitive to input slew").  Inputs get an ideal ramp (set_input_transition 0,
# the ETM index then is the port slew).  Output -> R45_ETMOUT (private dir).
source $::env(QC_FLOW)/common/lib.tcl
set corner $::env(QC_CORNER); set dir $::env(QC_PNR_OUT); set top $::env(QC_TOP)
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner]]
read_verilog $dir/out/$top.v
current_design $top
link_design
qc_apply_constraints $corner
set din [remove_from_collection [all_inputs] [get_ports {clk}]]
remove_driving_cell $din
set_input_transition 0 $din
set_propagated_clock [all_clocks]
read_parasitics -format spef $dir/out/${top}_${corner}_pt.spef
update_timing
file mkdir $::env(R45_ETMOUT)
extract_model -library_cell -output $::env(R45_ETMOUT)/${top}_$corner -format {lib}
puts "R45_ETM_DONE $corner"
exit
