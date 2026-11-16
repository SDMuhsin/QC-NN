# R6c probe (read-only, QB_FROM checkpoint, placement parasitics): clock arrival at the column-block clock pins vs top
# flops; one block -> top and one top -> block path with full clock expansion (-> rpt/clk_<db>.rpt); a latency summary.
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count 4
set s [qc_env QB_FROM cts]
qc_read_liberty
read_db $::OUT/db/$s.odb
read_sdc $::OUT/db/$s.sdc
qc_set_rc
set_propagated_clock [all_clocks]
estimate_parasitics -placement
set b [get_cells u_top/u_core/u_arr/g_c_3__u_col]
qc_to $::OUT/rpt/clk_$s.rpt {
    catch { report_clock_skew }
    report_checks -path_delay max -from $b -format full_clock_expanded -digits 3
    report_checks -path_delay max -to $b -format full_clock_expanded -digits 3
    report_checks -path_delay min -from $b -format full_clock_expanded -digits 3
    report_checks -path_delay max -to [get_pins u_top/u_core/u_arr/g_c_3__u_col/t2*] -format full_clock_expanded -digits 3
}
puts "PROBE_CLK done [expr {[clock seconds] - $::T0}] s"
