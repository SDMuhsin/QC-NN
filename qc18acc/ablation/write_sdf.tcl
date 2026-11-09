# DC: tt SDF of an ablation array netlist (qc18acc/ablation/remote.sh sdf), as qc18acc/gls/write_sdf.tcl with a
# generic top and no macros: tcbn65gplus tt, the synthesis SDC (impl/constraints.sdc) and WLM, pre-CTS.
# Environment: SYN (DC run dir), TOP, SDF (output), QC_FLOW, QC_SDC, QC_PERIOD.
source $::env(QC_FLOW)/common/lib.tcl
set top $::env(TOP)
set_host_options -max_cores 4
set_app_var search_path [concat . $::QC_LIBDIR [get_app_var search_path]]
set_app_var target_library [list [qc_db tt]]
set_app_var link_library [concat * [qc_db tt]]
read_verilog -netlist $::env(SYN)/$top.v
current_design $top
if {![link]} { puts "QC_ERROR link"; exit 1 }
set ::env(QC_CORNER) tt
qc_apply_constraints tt
set_operating_conditions $::QC_OC(tt) -library $::QC_LIB(tt)
puts "QC_WLM [qc_wire_load tt]"
report_timing -max_paths 1 -nosplit > tt_timing.rpt
report_timing -delay_type min -max_paths 1 -nosplit >> tt_timing.rpt
write_sdf -version 2.1 -context verilog $::env(SDF)
puts "QC_SDF_DONE $::env(SDF)"
exit 0
