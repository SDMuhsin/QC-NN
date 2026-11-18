# R21 helper: write the netlist of checkpoint QB_DB (for a PT dry run before the routed netlist exists) -> QB21_V
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env QB_DB cts_rt].odb
write_verilog $::env(QB21_V)
exit
