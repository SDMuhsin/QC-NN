# finish: DEF, routed netlist (without fillers; and with PG + fillers), pin / via dump for def2spef.py, final area and DRV reports.
set top [p TOP]
file mkdir $::OUT/out
write_def $::OUT/out/$top.def
write_verilog -remove_cells $::QC_PNR_FILL $::OUT/out/$top.v
write_verilog -include_pwr_gnd $::OUT/out/${top}_pg.v
source $::env(QC_FLOW)/pnr/or/dump_conn.tcl
qc_dump_conn $::OUT/out/$top.conn
estimate_parasitics -global_routing
qc_report final_est
qc_summary "final [qc_util]"
