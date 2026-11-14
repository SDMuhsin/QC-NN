# PrimeTime PX: average power of the qb_chip netlist (impl/r4/run.sh syn) from the R4 RTL SAIF windows (power.sh).
# tt library + macro tt .db, ideal clock (pre-CTS: no clock tree; ICGs only), SDC impl/constraints.sdc re-created per
# clock period, DC topographical parasitics (<top>.spef) when present (else the site wire-load), RTL -> gate names
# from DC's saif_map (saif_map.ptpx).  The macros' CLK internal power is 0 in the ARM .lib (qc18acc/power/macro_dat.py),
# so their access energy is added from the datatable (power.py); PT gives their pin + ICG power.
# Environment: QC_FLOW, SYN (DC run dir), QC_SDC, QC_EXTRA_DB_TT, R4_RUNS = "<period_ns> <saif> <out_prefix> ..." .
source $::env(QC_FLOW)/common/lib.tcl
set top qb_chip
set corner tt
set_app_var search_path [concat . $::QC_LIBDIR]
set_app_var link_path [concat * [qc_db $corner] [qc_extra_dbs tt]]
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
set_app_var power_default_toggle_rate 0
read_verilog $::env(SYN)/$top.v
current_design $top
link_design
set par wlm
if {[file exists $::env(SYN)/$top.spef] && ![catch {read_parasitics -format spef $::env(SYN)/$top.spef}]} { set par dc_topo_spef }
if {[file exists $::env(SYN)/saif_map.ptpx]} { source $::env(SYN)/saif_map.ptpx }
foreach {per saif o} $::env(R4_RUNS) {
    set ::env(QC_PERIOD) $per
    set ::env(QC_CORNER) $corner
    qc_apply_constraints $corner
    if {$par eq "wlm"} { set wlm [qc_wire_load $corner] }
    reset_switching_activity
    read_saif -strip_path tb_qb_chip/dut $saif
    update_power
    redirect ${o}_annot.rpt { report_switching_activity -list_not_annotated }
    redirect ${o}_hier.rpt  { report_power -nosplit -hierarchy -levels 4 }
    catch { redirect ${o}_hierclk.rpt { report_power -nosplit -hierarchy -levels 4 -groups clock_network } }
    set fh [open ${o}.txt w]
    puts $fh "period_ns $per corner $corner lib $::QC_LIB($corner) parasitics $par saif $saif"
    redirect -variable pr { report_power -nosplit }
    puts $fh [regsub {^.*?(Power Group)} $pr {\1}]
    redirect -variable sa { report_switching_activity }
    puts $fh [regsub {^.*?(Switching Activity Overview)} $sa {\1}]
    close $fh
}
exit
