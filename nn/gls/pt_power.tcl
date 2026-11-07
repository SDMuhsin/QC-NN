# PrimeTime PX: activity-based (SAIF) power of the KUL cluster netlist at tt (driven by nn/gls/power.sh).
# Environment: QC_FLOW (flow/tsmc65 of the synthesis tree), SYN (DC run dir: <top>.v, run.env values exported),
#   QC_SDC / QC_PERIOD (ns, = the cluster clock of the GLS that wrote the SAIF), QC_EXTRA_DB_TT (macro .db),
#   SAIF (file), SAIF_STRIP (instance path of the netlist top in the testbench), OUT (report prefix).
# Pre-CTS: ideal clock network (as in synthesis / STA), wire-load net capacitance.
source $::env(QC_FLOW)/common/lib.tcl
set top KULCluster_snax_KUL_cluster_wrapper
set corner tt
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs $corner]]
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
# Questa's SAIF omits nets that never toggled in the window: an unannotated net with no annotated fan-in is
# static (toggle 0), not the 0.1 / cycle default
set_app_var power_default_toggle_rate 0
read_verilog $::env(SYN)/$top.v
current_design $top
link_design
set ::env(QC_CORNER) $corner
qc_apply_constraints $corner
read_saif -strip_path $::env(SAIF_STRIP) $::env(SAIF)
update_power
set o $::env(OUT)
redirect ${o}_annot.rpt { report_switching_activity -list_not_annotated -show_pin }
redirect ${o}_power.rpt { report_power -nosplit -verbose }
redirect ${o}_hier.rpt  { report_power -nosplit -hierarchy -levels 3 }
# summary (design hierarchy and power groups only, no library cell names): the power-group table (memory =
# RF macros, clock_network = ICGs, ...), the hierarchy to depth 2 (i_snax_core_0_acc_0_snax_streamer_gemmX =
# GeMMX: streamer + GeMM array + SIMD rescale) and the annotation statistics
set fh [open ${o}.txt w]
puts $fh "period_ns $::env(QC_PERIOD) corner $corner saif $::env(SAIF)"
redirect -variable pr { report_power -nosplit }
puts $fh [regsub {^.*?(Power Group)} $pr {\1}]
redirect -variable ph { report_power -nosplit -hierarchy -levels 2 }
puts $fh [regsub {^.*?(Hierarchy)} $ph {\1}]
redirect -variable sa { report_switching_activity }
puts $fh [regsub {^.*?(Switching Activity Overview)} $sa {\1}]
close $fh
# NN_PT_HOOK: extra reports (e.g. qcacc/gls/pt_blocks.tcl)
if {[info exists ::env(NN_PT_HOOK)]} { source $::env(NN_PT_HOOK) }
exit
