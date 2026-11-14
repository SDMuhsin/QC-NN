# Area / QoR reports of a finished DC run from its .ddc (R4: the r4_chip_d reports were lost to a full disk).
# Environment as run_dc.sh (QC_FLOW, QC_EXTRA_DB_TT), SYN = run dir, OUT = report dir.
source $::env(QC_FLOW)/common/lib.tcl
set_app_var search_path [concat . $::QC_LIBDIR [get_app_var search_path]]
set_app_var target_library [list [qc_db tt]]
set_app_var link_library [concat * [qc_db tt] [qc_extra_dbs tt] dw_foundation.sldb]
read_ddc $::env(SYN)/qb_chip.ddc
current_design qb_chip
link
report_area -hierarchy -nosplit > $::env(OUT)/area.rpt
report_area -nosplit > $::env(OUT)/area_top.rpt
report_qor -nosplit > $::env(OUT)/qor.rpt
report_clock_gating -nosplit > $::env(OUT)/clock_gating.rpt
redirect $::env(OUT)/macro_cells.rpt {
    foreach_in_collection m [get_cells -hierarchical -filter "is_hierarchical==false && ref_name=~qb_*_*x*m*"] {
        puts "[get_object_name $m] [get_attribute $m ref_name] [get_attribute $m area]"
    }
}
puts "QB_DCRPT regs [sizeof_collection [all_registers]] cells [sizeof_collection [get_cells -hierarchical -filter is_hierarchical==false]]"
exit
