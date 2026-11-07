# DC: tt SDF of an ablation core netlist (as hw/kulcluster/gls/write_sdf.tcl, generic top).
# Environment: SYN (DC run dir), TOP, SDF (output), QC_FLOW (flow/tsmc65 of the tree).
source $::env(QC_FLOW)/common/lib.tcl
set top $::env(TOP)
set_host_options -max_cores 2
set_app_var search_path [concat . $::QC_LIBDIR [get_app_var search_path]]
set_app_var target_library [list [qc_db tt]]
set_app_var link_library [concat * [qc_db tt]]
read_verilog -netlist $::env(SYN)/$top.v
current_design $top
if {![link]} { puts "QC_ERROR link"; exit 1 }
set f [open $::env(SYN)/$top.sdc]; set sdc [read $f]; close $f
set sdc [string map [list $::QC_LIB(ss) $::QC_LIB(tt) $::QC_LIB(ff) $::QC_LIB(tt) \
                          $::QC_OC(ss) $::QC_OC(tt) $::QC_OC(ff) $::QC_OC(tt)] $sdc]
set f [open tt_$top.sdc w]; puts $f $sdc; close $f
source tt_$top.sdc
set_operating_conditions $::QC_OC(tt) -library $::QC_LIB(tt)
report_timing -max_paths 1 -nosplit > tt_timing_$top.rpt
write_sdf -version 2.1 -context verilog $::env(SDF)
puts "QC_SDF_DONE $::env(SDF)"
exit 0
