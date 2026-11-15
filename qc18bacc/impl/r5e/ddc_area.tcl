# R5e: area report of a finished DC run from its .ddc (the r5e_chip run filled the host disk while writing its reports).
#   QC_OUT=<syn run dir> QC_CORNER=tt QC_EXTRA_DB_TT=... dc_shell -f ddc_area.tcl   (impl/r5e/ddc_area.sh)
source $::env(QC_FLOW)/common/lib.tcl
set corner $::env(QC_CORNER)
set out    $::env(QC_OUT)
set_app_var search_path [concat . $::QC_LIBDIR [get_app_var search_path]]
set_app_var target_library [list [qc_db $corner]]
set_app_var synthetic_library dw_foundation.sldb
set_app_var link_library [concat * [qc_db $corner] [qc_extra_dbs $corner] dw_foundation.sldb]
read_ddc $out/$::env(QC_TOP).ddc
current_design $::env(QC_TOP)
link
report_area -hierarchy -nosplit > $out/rpt/area.rpt
redirect -variable ra {report_area -nosplit}
regexp -line {^Total cell area:\s+([0-9.]+)} $ra -> area
puts "R5E_DDC_AREA $area"
exit
