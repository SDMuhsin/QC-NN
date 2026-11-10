# Standalone area groups + xbar fan-in of a QC18-ACC netlist (impl/v4/area_run.sh): tt library + macro tt .db,
# links $SYN/qa_top.v, sources area_groups.tcl -> $SYN/rpt/area_groups.txt.
source $::env(QC_FLOW)/common/lib.tcl
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db tt] [qc_extra_dbs tt]]
read_verilog $::env(SYN)/qa_top.v
current_design qa_top
link_design
set out $::env(SYN)
set fh stdout
source [file join [file dirname [info script]] area_groups.tcl]
exit
