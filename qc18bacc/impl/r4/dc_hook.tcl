# QC_HOOK of impl/r4/run.sh (sourced after link + constraints, before compile): ARM macros dont_touch and listed,
# macro clock gates (hw/tech/qb_mem_tech.sv CKLNQD1) size-only, topographical context (utilisation QB_UTIL_T, default
# 0.70 as the slice; no floorplan: DC's own square die).
set mcs [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~qb_*_*x*m*"]
puts "QB_MACROS [sizeof_collection $mcs] instances of [lsort -unique [get_attribute -quiet $mcs ref_name]]"
if {[sizeof_collection $mcs]} { set_dont_touch $mcs }
redirect $::env(QC_OUT)/rpt/macro_cells.rpt {
    foreach_in_collection m $mcs { puts "[get_object_name $m] [get_attribute $m ref_name] [get_attribute $m area]" }
}
set mcg [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~CKLNQD*"]
puts "QB_MACRO_CG [sizeof_collection $mcg]"
if {[sizeof_collection $mcg]} { set_size_only -all_instances $mcg }
if {[shell_is_in_topographical_mode]} {
    set_utilization [qc_env QB_UTIL_T 0.70]
    puts "QB_TOPO util [qc_env QB_UTIL_T 0.70]"
}
if {[qc_env QC_ELAB_ONLY 0]} {
    redirect $::env(QC_OUT)/rpt/elab_area.rpt { report_area -hierarchy -nosplit }
    puts "QC_ELAB_ONLY done"; exit
}
# RTL-SAIF name mapping for PTPX (QB_SAIF_MAP=1): saif_map from elaboration, written by dc_post.tcl after compile.
if {[qc_env QB_SAIF_MAP 0]} { saif_map -start; puts "QB_SAIF_MAP start" }
