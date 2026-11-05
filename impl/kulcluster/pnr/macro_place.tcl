# Macro floorplan of the KUL cluster (sourced by kulcluster.cfg): sets P(DIE_AREA), P(CORE_AREA), P(MACRO_PLACE).
# 38 ARM RF macros in two banks along the top and bottom edges, every macro with its pin edge (the macros have all
# signal pins on one long edge, 12.8 um inside the outline; the I-cache data macros also have D on the opposite
# edge) towards the logic in the middle.  The macros block M1-M3 only, so the outer rows reach the logic over the
# inner rows on M4-M7.
#   top    (R0, pins down):  T1, T2: 6 TCDM banks each;  T3: TCDM, I-cache (data 0.0 0.1, tag 0 1, data 1.0 1.1), 2 TCDM
#   bottom (MX, pins up):    B1, B2: 6 TCDM banks each;  B3: 5 TCDM banks
# Gaps 2 x halo between macros (no rows left in them), macro rows on the 1.8 um row grid.
# Die 2820 x 2462 um, core 2800 x 2440.8 um (58.4 % utilisation at the DC area of 3.99 mm2; after electrical
# repair the cells grow by ~50 %, see pre_cts.tcl); the logic sits in a 2800 x ~1520 um band between the banks plus
# the pockets at the ends of the rows.  (Iteration 1: die 2620 x 2322 um, core 66.8 %, was too full after repair:
# 84 % and detailed placement failed after CTS.)
set kul_halo 10.0
set kul_gap  [expr {2 * $kul_halo}]
set kul_cx0 10.0; set kul_cy0 10.8; set kul_cx1 2810.0; set kul_cy1 2451.6
set ::KUL_DIE_H 2462
set P(DIE_AREA)  [list 0 0 2820 $::KUL_DIE_H]
set P(CORE_AREA) [list $kul_cx0 $kul_cy0 $kul_cx1 $kul_cy1]
set P(MACRO_HALO) [list $kul_halo $kul_halo]
array set kul_wh {T {397.97 133.29} D {230.65 146.785} t {117.23 146.785}}
set kul_tcdm  {i_cluster/i_snitch_data_mem/gen_banks_%d__i_data_mem/i_tc_sram/gen_macro_gen_rf_512x64_i_macro}
set kul_ic    i_cluster/gen_hive_0__i_snitch_hive/i_snitch_icache/i_lookup
set kul_idata "$kul_ic/i_snitch_icache_data/g_cache_data_sets_%d__i_data/i_tc_sram/gen_macro_gen_rf_128xk128_gen_tile_%d__i_macro"
set kul_itag  "$kul_ic/i_snitch_icache_tag/g_cache_tag_sets_%d__i_tag/i_tc_sram/gen_macro_gen_rf_128x40_i_macro"
proc kul_snap {v g o dir} {
    set k [expr {($v - $o) / $g}]
    set k [expr {$dir eq "down" ? floor($k + 1e-6) : ceil($k - 1e-6)}]
    return [format %.3f [expr {$o + $k * $g}]]
}
# one row: list of {kind inst}, centred in the core, lower edge y, orientation
proc kul_row {items y orient} {
    global kul_wh kul_gap kul_cx0 kul_cx1
    set w [expr {-$kul_gap}]
    foreach it $items { set w [expr {$w + [lindex $kul_wh([lindex $it 0]) 0] + $kul_gap}] }
    set x [kul_snap [expr {($kul_cx0 + $kul_cx1 - $w) / 2.0}] 0.2 0.0 down]
    set out {}
    foreach it $items {
        lappend out [list [lindex $it 1] $x $y $orient]
        set x [kul_snap [expr {$x + [lindex $kul_wh([lindex $it 0]) 0] + $kul_gap}] 0.2 0.0 up]
    }
    return $out
}
set kul_b 0
proc kul_banks {n} {
    global kul_b kul_tcdm
    set l {}
    for {set i 0} {$i < $n} {incr i} { lappend l [list T [format $kul_tcdm $kul_b]]; incr kul_b }
    return $l
}
set kul_hT [lindex $kul_wh(T) 1]; set kul_hD [lindex $kul_wh(D) 1]
set yT1 [kul_snap [expr {$kul_cy1 - $kul_hT}] 1.8 $kul_cy0 down]
set yT2 [kul_snap [expr {$yT1 - $kul_gap - $kul_hT}] 1.8 $kul_cy0 down]
set yT3 [kul_snap [expr {$yT2 - $kul_gap - $kul_hD}] 1.8 $kul_cy0 down]
set yB1 $kul_cy0
set yB2 [kul_snap [expr {$yB1 + $kul_hT + $kul_gap}] 1.8 $kul_cy0 up]
set yB3 [kul_snap [expr {$yB2 + $kul_hT + $kul_gap}] 1.8 $kul_cy0 up]
set P(MACRO_PLACE) {}
lappend P(MACRO_PLACE) {*}[kul_row [kul_banks 6] $yT1 R0]
lappend P(MACRO_PLACE) {*}[kul_row [kul_banks 6] $yT2 R0]
set t3 [kul_banks 1]
lappend t3 [list D [format $kul_idata 0 0]] [list D [format $kul_idata 0 1]] \
    [list t [format $kul_itag 0]] [list t [format $kul_itag 1]] \
    [list D [format $kul_idata 1 0]] [list D [format $kul_idata 1 1]]
lappend t3 {*}[kul_banks 2]
lappend P(MACRO_PLACE) {*}[kul_row $t3 $yT3 R0]
lappend P(MACRO_PLACE) {*}[kul_row [kul_banks 6] $yB1 MX]
lappend P(MACRO_PLACE) {*}[kul_row [kul_banks 6] $yB2 MX]
lappend P(MACRO_PLACE) {*}[kul_row [kul_banks 5] $yB3 MX]
set P(MACRO_AUTO) 0
# y span of the logic band (IO pins go on the left / right edges there, pins.tcl)
set ::KUL_IO_Y0 [expr {$yB3 + $kul_hT + $kul_halo}]
set ::KUL_IO_Y1 [expr {$yT3 - $kul_halo}]
