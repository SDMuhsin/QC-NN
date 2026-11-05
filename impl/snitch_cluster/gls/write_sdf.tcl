# DC: SDF of the snitch_cluster_wrapper netlist at tt (wire-load mode, pre-CTS: the cells of the
# ideal clock network still have their own delays in the SDF; their names go to clock_cells.txt
# for sdf_idealclk.py). Run by gls.sh sdf on the DC host, in the DC run's tree.
# Environment: SYN (DC run dir of the netlist), SDF (output), QC_EXTRA_DB_TT (macro .db, run.env),
#              QC_FLOW (flow/tsmc65 of the synthesis tree: library names / paths).
source $::env(QC_FLOW)/common/lib.tcl
set top snitch_cluster_wrapper
set_host_options -max_cores 8
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
# combinational cells and clock gates between the clock port and the register clock pins
set ck [all_fanout -clock_tree -flat -only_cells]
set ck [filter_collection $ck "is_sequential == false || ref_name =~ CKLNQD*"]
set f [open clock_cells.txt w]
foreach_in_collection c $ck { puts $f "[get_object_name $c] [get_attribute $c ref_name]" }
close $f
puts "QC_CLOCK_CELLS [sizeof_collection $ck]"
write_sdf -version 2.1 -context verilog $::env(SDF)
puts "QC_SDF_DONE $::env(SDF)"
exit 0
