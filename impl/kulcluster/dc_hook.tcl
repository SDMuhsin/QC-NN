# DC settings of the KUL cluster (QC_HOOK of flow/tsmc65/syn/run_dc.sh: sourced after link and constraints, before
# compile).  QC_ELAB_ONLY=1: stop after elaboration (rpt/elab_*.rpt), no compile.
set mcs [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~kul_rf_*"]
puts "QC_MACROS [sizeof_collection $mcs] instances of [lsort -unique [get_attribute -quiet $mcs ref_name]]"
if {[sizeof_collection $mcs]} { set_dont_touch $mcs }
set ckc [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~CK*"]
puts "QC_CLOCK_CELLS [sizeof_collection $ckc] [lsort -unique [get_attribute -quiet $ckc ref_name]]"
redirect $::env(QC_OUT)/rpt/macro_cells.rpt {
    foreach_in_collection m $mcs { puts "[get_object_name $m] [get_attribute $m ref_name]" }
    foreach_in_collection m $ckc { puts "[get_object_name $m] [get_attribute $m ref_name]" }
}
if {[qc_env QC_ELAB_ONLY 0]} {
    redirect $::env(QC_OUT)/rpt/elab_area.rpt  { report_area -hierarchy -nosplit }
    redirect $::env(QC_OUT)/rpt/elab_check_timing.rpt { check_timing }
    puts "QC_ELAB_ONLY done"
    exit
}
