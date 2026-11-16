# R11: path detail probe (run.sh sta with QB11_STA_TCL=sta_paths.tcl) after sta_rt.tcl's load + repair (QB11_PATHS: list of {from to} pin pairs) -> rpt/paths11.rpt
source $::env(QB11_DIR)/sta_rt.tcl
set ::env(QB11_PROPA) 0
source $::QB_R11/propa.tcl
set k 0
foreach pr [qb_env QB11_PATHS {}] {
    lassign $pr a b
    qc_to $::OUT/rpt/paths11_[incr k].rpt { report_checks -through [get_pins $a] -to [get_pins $b] -format full_clock_expanded -fields {slew cap fanout} -digits 3 }
}
foreach c {u_hub/clk u_act_blk/clk u_top_u_core_u_arr_g_c_0__u_col/clk u_top_u_core_u_arr_g_c_7__u_col/clk} {
    qc_log "r11 clkarr $c [qb11_arr $c]"
}
