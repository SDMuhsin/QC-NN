# DC: tt SDF of a QC18-ACC netlist (qc18acc/gls/run_gls.sh sdf), the delays PrimeTime signed off at tt:
# tcbn65gplustc_ccs + macro tt .db, wire-load mode with the synthesis WLM (qc_wire_load: WireAreaLowkCon enclosed),
# pre-CTS (no clock tree; the ICGs' own delays are in the SDF and zeroed later by flow/tsmc65/sim/sdf_idealclk.py).
# Environment: SYN (DC run dir: qa_top.v, run.env values exported: QC_EXTRA_DB_TT, QC_SDC, QC_PERIOD), SDF (output),
#   QC_FLOW (flow/tsmc65, site / library names).  Same structure as hw/kulcluster/gls/write_sdf.tcl.
source $::env(QC_FLOW)/common/lib.tcl
set top qa_top
set_host_options -max_cores 4
set_app_var search_path [concat . $::QC_LIBDIR [get_app_var search_path]]
set_app_var target_library [list [qc_db tt]]
set_app_var link_library [concat * [qc_db tt] [qc_extra_dbs tt]]
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
