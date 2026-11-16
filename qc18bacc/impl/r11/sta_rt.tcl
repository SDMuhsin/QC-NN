# R11 timing probe (read-only on the run: nothing saved) of <run>/db/<QB_DB>.odb [grt]: qc_load (SDC, propagated clock
# after CTS), DRV repair of the signal nets at QB_MAXTRAN [0.4] (the place-step repair the no-repair run r11_c skipped;
# buffers left unlegalised: estimate only), placement parasitics, top classes (classes.tcl) -> rpt/classes_<corner>.txt
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qb_env QB_DB grt]
set_max_transition [qb_env QB_MAXTRAN 0.4] [current_design]
estimate_parasitics -placement
set ::QB_R11 $::env(QB11_DIR)
# QB11_PROPA_STA 1: apply proposal A here (db before the route step's PRE_ROUTE hook, e.g. cts)
if {[qb_env QB11_PROPA_STA 0]} { source $::QB_R11/propa.tcl }
# QB11_IDEAL_A 1 (pre-CTS db, ideal clock): proposal A as R8d's model - column clk pins at -QB11_INS [0.96] ns latency
if {[qb_env QB11_IDEAL_A 0]} { set_clock_latency [expr {-[qb_env QB11_INS 0.96]}] [get_pins u_top_u_core_u_arr_g_c_*__u_col/clk] }
if {[qb_env QB11_RD 1]} { repair_design -max_utilization 99 }
estimate_parasitics -placement
set ::QB_R11 $::env(QB11_DIR)
source $::QB_R11/classes.tcl
