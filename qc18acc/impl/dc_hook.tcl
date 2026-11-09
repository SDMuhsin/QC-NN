# DC settings of QC18-ACC (QC_HOOK of flow/tsmc65/syn/run_dc.sh: sourced after link and constraints, before compile).
# Macros (hw/tech/qa_sram_tech.sv) dont_touch + listed; QC_ELAB_ONLY=1 stops after elaboration (rpt/elab_*.rpt).
set mcs [get_cells -quiet -hierarchical -filter "is_hierarchical==false && (ref_name=~qa_act_* || ref_name=~qa_wgt_* || ref_name=~qa_par_* || ref_name=~qa_dsc_*)"]
puts "QC_MACROS [sizeof_collection $mcs] instances of [lsort -unique [get_attribute -quiet $mcs ref_name]]"
if {[sizeof_collection $mcs]} { set_dont_touch $mcs }
redirect $::env(QC_OUT)/rpt/macro_cells.rpt {
    foreach_in_collection m $mcs { puts "[get_object_name $m] [get_attribute $m ref_name]" }
}
if {[qc_env QC_ELAB_ONLY 0]} {
    redirect $::env(QC_OUT)/rpt/elab_area.rpt  { report_area -hierarchy -nosplit }
    redirect $::env(QC_OUT)/rpt/elab_check_timing.rpt { check_timing }
    puts "QC_ELAB_ONLY done"
    exit
}
# v2 macro clock gates (hw/tech/qa_sram_tech.sv u_cg, CKLNQD): keep them (any drive strength); DC sees them as
# pre-existing integrated clock gates (report_clock_gating, rpt/clock_gating.rpt).
set mcg [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~CKLNQD*"]
puts "QC_MACRO_CG [sizeof_collection $mcg] macro clock gates"
if {[sizeof_collection $mcg]} { set_size_only -all_instances $mcg }
