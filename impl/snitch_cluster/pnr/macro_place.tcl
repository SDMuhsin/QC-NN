# Macro floorplan of the Snitch FP cluster (sourced by snitch_fp.cfg): sets P(DIE_AREA), P(CORE_AREA), P(MACRO_PLACE).
# 16 TCDM banks (qc_sp_1024x64m8, 646.5 x 177.6 um, all signal pins on M1-M4 along one long edge, 28.8 um inside)
# in four rows of 4: two rows along the top edge (R0, pins down), two along the bottom edge (MX, pins up); the
# outer rows reach the logic over the inner rows on M5-M7 (the macro blocks M1-M4).  The 4 I-cache data macros
# (qc_rf_16x128m1, 225.8 x 87.0 um, Q / control on the lower edge, D near the upper edge, blocks M1-M3) sit 2 x 2
# in the logic band just below the first inner top TCDM bank, R0.  The TCDM rows leave a ~480 um wide column of
# standard cells at their left end (x 10-492 um, full core height), so the M4 core straps there connect the M7
# straps over the TCDM rows to the rest of the grid (with the I-cache macros in that column, or rows spanning the
# whole core width, the top part of the grid was cut off: PSM-0069).
# Gaps 2 x halo, macro y on the 1.8 um row grid, x on 0.2 um.
# Die 3160 x 3000 um, core 3140 x 2977.2 um (62 % utilisation at the DC area of 5.80 mm2); the logic sits in a
# 3140 x ~2200 um band between the banks plus the left column.
set sn_halo 10.0
set sn_gap  [expr {2 * $sn_halo}]
set sn_cx0 10.0; set sn_cy0 10.8; set sn_cx1 3150.0; set sn_cy1 2988.0
set P(DIE_AREA)  {0 0 3160 3000}
set P(CORE_AREA) [list $sn_cx0 $sn_cy0 $sn_cx1 $sn_cy1]
set P(MACRO_HALO) [list $sn_halo $sn_halo]
array set sn_wh {S {646.525 177.605} R {225.85 86.965}}
set sn_tcdm {i_cluster/gen_tcdm_super_bank_%d__gen_tcdm_bank_%d__i_data_mem/i_tc_sram/gen_macro_gen_sp_1024x64_i_macro}
set sn_ic   {i_cluster/gen_hive_0__i_snitch_hive/i_snitch_icache/gen_parallel_lookup_i_lookup/g_sets_%d__i_data/i_tc_sram/gen_macro_gen_rf_16xk128_gen_tile_%d__i_macro}
proc sn_snap {v g o dir} {
    set k [expr {($v - $o) / $g}]
    set k [expr {$dir eq "down" ? floor($k + 1e-6) : ceil($k - 1e-6)}]
    return [format %.3f [expr {$o + $k * $g}]]
}
set hS [lindex $sn_wh(S) 1]
set yT1 [sn_snap [expr {$sn_cy1 - $hS}] 1.8 $sn_cy0 down]            ;# outer top row
set yT2 [sn_snap [expr {$yT1 - $sn_gap - $hS}] 1.8 $sn_cy0 down]      ;# inner top row
set yB1 $sn_cy0                                                       ;# outer bottom row
set yB2 [sn_snap [expr {$yB1 + $hS + $sn_gap}] 1.8 $sn_cy0 up]        ;# inner bottom row
# TCDM columns: first at 492 um (left standard-cell column); I-cache columns below the first TCDM column
set xS  [list [sn_snap [expr {$sn_cx0 + 2 * [lindex $sn_wh(R) 0] + 2 * $sn_gap}] 0.2 0.0 up]]
set xR0 [lindex $xS 0]
set xR1 [sn_snap [expr {$xR0 + [lindex $sn_wh(R) 0] + $sn_gap}] 0.2 0.0 up]
for {set i 1} {$i < 4} {incr i} {
    lappend xS [sn_snap [expr {[lindex $xS end] + [lindex $sn_wh(S) 0] + $sn_gap}] 0.2 0.0 up]
}
if {[lindex $xS end] + [lindex $sn_wh(S) 0] > $sn_cx1} { error "macro_place: TCDM rows wider than the core" }
set P(MACRO_PLACE) {}
# super bank 0: top (bank 0-3 outer, 4-7 inner); super bank 1: bottom (bank 0-3 outer, 4-7 inner)
for {set i 0} {$i < 4} {incr i} {
    set x [lindex $xS $i]
    lappend P(MACRO_PLACE) [list [format $sn_tcdm 0 $i] $x $yT1 R0] [list [format $sn_tcdm 0 [expr {$i + 4}]] $x $yT2 R0]
    lappend P(MACRO_PLACE) [list [format $sn_tcdm 1 $i] $x $yB1 MX] [list [format $sn_tcdm 1 [expr {$i + 4}]] $x $yB2 MX]
}
# I-cache: set s in column s, tile 0 upper, tile 1 lower, below the inner top TCDM row
set hR [lindex $sn_wh(R) 1]
set yR0 [sn_snap [expr {$yT2 - $sn_gap - $hR}] 1.8 $sn_cy0 down]
set yR1 [sn_snap [expr {$yR0 - $sn_gap - $hR}] 1.8 $sn_cy0 down]
foreach s {0 1} x [list $xR0 $xR1] {
    lappend P(MACRO_PLACE) [list [format $sn_ic $s 0] $x $yR0 R0] [list [format $sn_ic $s 1] $x $yR1 R0]
}
set P(MACRO_AUTO) 0
# y span of the logic band (IO pins on the left / right edges there, pins.tcl)
set ::SN_IO_Y0 [expr {$yB2 + $hS + $sn_halo}]
set ::SN_IO_Y1 [expr {$yT2 - $sn_halo}]
