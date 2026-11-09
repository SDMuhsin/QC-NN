# Macro floorplan of QC18-ACC (sourced by qa.cfg): P(DIE_AREA), P(CORE_AREA), P(MACRO_PLACE).
# Horizontal tiers, symmetric about the logic band in the middle (PE array, xbar, PPU, AGU, head):
#   top    (R0, signal pins on the lower edge, facing down):  W_top: wgt 0 1 2 + par 0 | T3: act buf 2 banks 0-3 |
#          T2: act buf 0 banks 4-7 | T1: act buf 0 banks 0-3 (+ descriptor RF at the right end)
#   [logic band, QA_BAND um between the macro edges; IO pins on its left / right edges]
#   bottom (MX, pins on the upper edge, facing up): B1: act buf 1 banks 0-3 | B2: buf 1 banks 4-7 | B3: buf 2 banks
#          4-7 | W_bot: wgt 3 4 5 + par 1
# The ARM sram_sp_adv macros have every signal pin on one long edge (28.8 um inside the outline, pin shapes on
# M1-M4, OBS M1-M4 over the whole macro), PG rings VDDCE / VDDPE / VSSE on M3 (horizontal) and M4 (vertical):
# routing crosses the macros on M5-M7.  Gaps 2 x halo between macros, macro rows on the 1.8 um row grid.
set qa_halo 10.0
set qa_gap  [expr {2 * $qa_halo}]
set qa_band [expr {[info exists ::env(QA_BAND)] ? $::env(QA_BAND) : 450.0}]
array set qa_wh {A {646.525 177.605} W {780.925 453.365} P {713.725 453.365} D {146.99 139.52}}
set qa_cx0 10.0; set qa_cy0 10.8
set qa_tierw [expr {3 * 780.925 + 713.725 + 3 * $qa_gap}]
set qa_cx1 [expr {ceil(($qa_cx0 + $qa_tierw + 20.0) / 0.2) * 0.2}]
proc qa_snap {v g o dir} {
    set k [expr {($v - $o) / $g}]
    set k [expr {$dir eq "down" ? floor($k + 1e-6) : ceil($k - 1e-6)}]
    return [format %.3f [expr {$o + $k * $g}]]
}
proc qa_row {items y orient} {   ;# one row of {kind inst}, centred in the core, lower edge y
    global qa_wh qa_gap qa_cx0 qa_cx1
    set w [expr {-$qa_gap}]
    foreach it $items { set w [expr {$w + [lindex $qa_wh([lindex $it 0]) 0] + $qa_gap}] }
    set x [qa_snap [expr {($qa_cx0 + $qa_cx1 - $w) / 2.0}] 0.2 0.0 down]
    set out {}
    foreach it $items {
        lappend out [list [lindex $it 1] $x $y $orient]
        set x [qa_snap [expr {$x + [lindex $qa_wh([lindex $it 0]) 0] + $qa_gap}] 0.2 0.0 up]
    }
    return $out
}
proc qa_act {buf banks} {
    set l {}
    foreach b $banks { lappend l [list A [format {u_act/g_buf_%d__g_bank_%d__u_ram/g_mac_g_act_u_mac} $buf $b]] }
    return $l
}
proc qa_w {banks par} {
    set l {}
    foreach b $banks { lappend l [list W [format {u_wmem/g_bank_%d__u_ram/g_mac_g_wgt_u_mac} $b]] }
    lappend l [list P [format {u_pmem/g_bank_%d__u_ram/g_mac_g_par_u_mac} $par]]
    return $l
}
set hA [lindex $qa_wh(A) 1]; set hW [lindex $qa_wh(W) 1]
set qa_edge [expr {[info exists ::env(QA_EDGE)] ? $::env(QA_EDGE) : 20.0}]  ;# rows between the outer tiers and the core edge (0: pdngen fails, PDN-0232)
set yBw [qa_snap [expr {$qa_cy0 + $qa_edge}] 1.8 $qa_cy0 up]
set yB3 [qa_snap [expr {$yBw + $hW + $qa_gap}] 1.8 $qa_cy0 up]
set yB2 [qa_snap [expr {$yB3 + $hA + $qa_gap}] 1.8 $qa_cy0 up]
set yB1 [qa_snap [expr {$yB2 + $hA + $qa_gap}] 1.8 $qa_cy0 up]
set yT1 [qa_snap [expr {$yB1 + $hA + $qa_band}] 1.8 $qa_cy0 up]
set yT2 [qa_snap [expr {$yT1 + $hA + $qa_gap}] 1.8 $qa_cy0 up]
set yT3 [qa_snap [expr {$yT2 + $hA + $qa_gap}] 1.8 $qa_cy0 up]
set yTw [qa_snap [expr {$yT3 + $hA + $qa_gap}] 1.8 $qa_cy0 up]
set qa_cy1 [qa_snap [expr {$yTw + $hW + $qa_edge}] 1.8 $qa_cy0 up]
set ::QA_DIE_W [expr {$qa_cx1 + 10.0}]
set ::QA_DIE_H [expr {$qa_cy1 + 10.8}]
set P(DIE_AREA)  [list 0 0 $::QA_DIE_W $::QA_DIE_H]
set P(CORE_AREA) [list $qa_cx0 $qa_cy0 $qa_cx1 $qa_cy1]
set P(MACRO_HALO) [list $qa_halo $qa_halo]
set P(MACRO_PLACE) {}
lappend P(MACRO_PLACE) {*}[qa_row [qa_w {0 1 2} 0] $yTw R0]
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 2 {0 1 2 3}] $yT3 R0]
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 0 {4 5 6 7}] $yT2 R0]
set t1 [qa_row [qa_act 0 {0 1 2 3}] $yT1 R0]
lappend P(MACRO_PLACE) {*}$t1
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 1 {0 1 2 3}] $yB1 MX]
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 1 {4 5 6 7}] $yB2 MX]
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 2 {4 5 6 7}] $yB3 MX]
lappend P(MACRO_PLACE) {*}[qa_row [qa_w {3 4 5} 1] $yBw MX]
# descriptor RF: right of row T1, pins down into the band
set xl [lindex [lindex $t1 end] 1]
lappend P(MACRO_PLACE) [list u_desc/g_mac_g_dsc_u_mac [qa_snap [expr {$xl + [lindex $qa_wh(A) 0] + $qa_gap}] 0.2 0.0 up] $yT1 R0]
set P(MACRO_AUTO) 0
set ::QA_IO_Y0 [expr {$yB1 + $hA + $qa_halo}]
set ::QA_IO_Y1 [expr {$yT1 - $qa_halo}]
