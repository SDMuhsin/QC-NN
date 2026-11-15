# impl/r6b: geometry of the ICG outputs of a checkpoint (QB_RUN, QB_DB default cts), odb only (results/r6b.md):
# output-net bbox half-perimeter per ICG (histogram), locations along the R6b post-CTS worst path.
read_db $::env(QB_RUN)/db/[expr {[info exists ::env(QB_DB)] ? $::env(QB_DB) : "cts"}].odb
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set h {0 0 0 0 0}; set l {}
foreach i [$blk getInsts] {
    if {![regexp {^CKL} [[$i getMaster] getName]]} continue
    foreach t [$i getITerms] {
        if {![$t isOutputSignal] || [$t getNet] eq "NULL"} continue
        set b [[$t getNet] getTermBBox]
        set hp [expr {([$b dx] + [$b dy]) / $u}]
        set k [expr {$hp > 1000 ? 4 : $hp > 500 ? 3 : $hp > 200 ? 2 : $hp > 50 ? 1 : 0}]
        lset h $k [expr {[lindex $h $k] + 1}]; lappend l [list [$i getName] $hp]
    }
}
puts "ICGNET hpwl_um_hist <=50 [lindex $h 0] 50-200 [lindex $h 1] 200-500 [lindex $h 2] 500-1000 [lindex $h 3] >1000 [lindex $h 4]"
foreach e [lrange [lsort -real -decreasing -index 1 $l] 0 4] { puts [format "ICGNET_WORST %s hpwl_um %.0f" {*}$e] }
foreach n {u_top/g_r3b_u_prm/clk_gate_stg_t_reg_19/latch clkbuf_0_u_top/g_r3b_u_prm/net134827
           clkbuf_2_1__f_u_top/g_r3b_u_prm/net134827 u_top/g_r3b_u_prm/stg_t_reg_441_ clkbuf_leaf_2571_clk
           clkbuf_level_1_2_242711934_clk wire43304 wire43303 wire43302 u_top/u_core/u_arr/g_c_3__u_col} {
    set i [$blk findInst $n]
    if {$i eq "NULL"} { puts "LOC $n not_found"; continue }
    set b [$i getBBox]
    puts [format "LOC %s x %.0f y %.0f (bbox %.0f %.0f %.0f %.0f)" $n [expr {[$b xMin] / $u}] [expr {[$b yMin] / $u}] \
        [expr {[$b xMin] / $u}] [expr {[$b yMin] / $u}] [expr {[$b xMax] / $u}] [expr {[$b yMax] / $u}]]
}
exit
