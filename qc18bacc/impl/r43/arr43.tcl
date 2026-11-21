# R43 probe: per path-analysis-point clock arrival at a few sinks (which list index = which corner / min-max) vs
# sta::vertex_worst_arrival_path (what impl/r14/clk14.tcl uses).  Via impl/r29/or29.sh <tag> arr43.tcl <log>; R43_DB [cts].
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R43_DB cts]
estimate_parasitics -placement
report_worst_slack -max
puts "R43_CORNERS [lmap c [sta::corners] {$c name}]"
set clk [lindex [get_clocks qb_clk] 0]
foreach pn {u_hub/clk u_act_blk/clk u_top_u_core_u_arr_g_c_0__u_col/clk u_top_g_hwn_wc_d_reg_0__75_/CP} {
    set p [get_pins -quiet $pn]; if {$p eq ""} { puts "R43_ARR $pn missing"; continue }
    foreach v [$p vertices] { if {$v eq "NULL"} continue
        set w [sta::vertex_worst_arrival_path $v max]
        puts "R43_ARR $pn worst [expr {$w eq "NULL" ? "NA" : [$w arrival]}] aps [$v arrivals_clk rise $clk rise]"
    }
}
