# DC: SDF of the KUL cluster netlist at the tt corner (tcbn65gplustc_ccs, NCCOM, wire-load mode,
# pre-CTS: no clock tree, the ICG cells' own delays are in the SDF). Driven by gls.sh sdf.
# Environment: SYN (DC run dir of the netlist), SDF (output), QC_EXTRA_DB_TT (macro .db, run.env),
#              QC_FLOW (flow/tsmc65 of the synthesis tree, for site / library names).
source $::env(QC_FLOW)/common/lib.tcl
set top KULCluster_snax_KUL_cluster_wrapper
set_host_options -max_cores 4
set_app_var search_path [concat . $::QC_LIBDIR [get_app_var search_path]]
set_app_var target_library [list [qc_db tt]]
set_app_var link_library [concat * [qc_db tt] [qc_extra_dbs tt]]
read_verilog -netlist $::env(SYN)/$top.v
current_design $top
if {![link]} { puts "QC_ERROR link"; exit 1 }
# the synthesis SDC, retargeted from the ss to the tt library / operating condition
set f [open $::env(SYN)/$top.sdc]; set sdc [read $f]; close $f
set sdc [string map [list $::QC_LIB(ss) $::QC_LIB(tt) $::QC_LIB(ff) $::QC_LIB(tt) \
                          $::QC_OC(ss) $::QC_OC(tt) $::QC_OC(ff) $::QC_OC(tt)] $sdc]
set f [open tt.sdc w]; puts $f $sdc; close $f
source tt.sdc
set_operating_conditions $::QC_OC(tt) -library $::QC_LIB(tt)
report_timing -max_paths 1 -nosplit > tt_timing.rpt
report_timing -delay_type min -max_paths 1 -nosplit >> tt_timing.rpt
write_sdf -version 2.1 -context verilog $::env(SDF)
puts "QC_SDF_DONE $::env(SDF)"
exit 0
