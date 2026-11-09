# Macro floorplan of QC18-ACC v3 (sourced by qa3.cfg): P(DIE_AREA), P(CORE_AREA), P(MACRO_PLACE).
# Same scheme as the v2 macro_place.tcl (horizontal tiers, symmetric about the logic band, every signal-pin edge
# facing the band), with the v3 memories: 48 act halves qa_act_512x64m4 (rf_sp_adv, 397.97 x 133.29 um, pins on
# one long edge, rings / OBS on M1-M3 only), even / odd weight halves u_wmem_e / u_wmem_o (3 x 4096x80 each).
#   top    (R0, pins down):  W_top: wgt_e 0 1 2 + par 0 + descriptor RF | T3: buf 2 lo halves banks 0-7 |
#          T2: buf 1 lo banks 0-7 | T1: buf 0 lo banks 0-7
#   [logic band, QA_BAND um (default 700) between the macro edges; IO pins on its left edge]
#   bottom (MX, pins up):    B1: buf 0 hi halves banks 0-7 | B2: buf 1 hi | B3: buf 2 hi | W_bot: wgt_o 0 1 2 + par 1
# A bank's two halves (lo h = 0, hi h = 1) mirror each other about the band; one row = one buffer's 8 banks.
set qa_halo 10.0
set qa_gap  [expr {[info exists ::env(QA_GAP)] ? $::env(QA_GAP) : 60.0}]
set qa_hgap [expr {2 * $qa_halo}]
set qa_band [expr {[info exists ::env(QA_BAND)] ? $::env(QA_BAND) : 700.0}]
array set qa_wh {A {397.97 133.29} W {780.925 453.365} P {713.725 453.365} D {146.99 139.52}}
set qa_cx0 10.0; set qa_cy0 10.8
set qa_tierw [expr {max(3 * 780.925 + 713.725 + 146.99 + 4 * $qa_hgap, 8 * 397.97 + 7 * $qa_hgap)}]
set qa_cx1 [expr {ceil(($qa_cx0 + $qa_tierw + 20.0) / 0.2) * 0.2}]
proc qa_snap {v g o dir} {
    set k [expr {($v - $o) / $g}]
    set k [expr {$dir eq "down" ? floor($k + 1e-6) : ceil($k - 1e-6)}]
    return [format %.3f [expr {$o + $k * $g}]]
}
proc qa_row {items y orient} {   ;# one row of {kind inst}, centred in the core, lower edge y
    global qa_wh qa_hgap qa_cx0 qa_cx1
    set w [expr {-$qa_hgap}]
    foreach it $items { set w [expr {$w + [lindex $qa_wh([lindex $it 0]) 0] + $qa_hgap}] }
    set x [qa_snap [expr {($qa_cx0 + $qa_cx1 - $w) / 2.0}] 0.2 0.0 down]
    set out {}
    foreach it $items {
        lappend out [list [lindex $it 1] $x $y $orient]
        set x [qa_snap [expr {$x + [lindex $qa_wh([lindex $it 0]) 0] + $qa_hgap}] 0.2 0.0 up]
    }
    return $out
}
proc qa_act {buf h} {
    set l {}
    for {set b 0} {$b < 8} {incr b} { lappend l [list A [format {u_act/g_buf_%d__g_bank_%d__g_half_%d__u_ram/g_mac_g_act_u_mac} $buf $b $h]] }
    return $l
}
proc qa_w {half par desc} {
    set l {}
    foreach b {0 1 2} { lappend l [list W [format {u_wmem_%s/g_bank_%d__u_ram/g_mac_g_wgt_u_mac} $half $b]] }
    lappend l [list P [format {u_pmem/g_bank_%d__u_ram/g_mac_g_par_u_mac} $par]]
    if {$desc} { lappend l [list D u_desc/g_mac_g_dsc_u_mac] }
    return $l
}
set hA [lindex $qa_wh(A) 1]; set hW [lindex $qa_wh(W) 1]
set qa_edge [expr {[info exists ::env(QA_EDGE)] ? $::env(QA_EDGE) : 20.0}]
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
lappend P(MACRO_PLACE) {*}[qa_row [qa_w e 0 1] $yTw R0]
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 2 0] $yT3 R0]
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 1 0] $yT2 R0]
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 0 0] $yT1 R0]
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 0 1] $yB1 MX]
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 1 1] $yB2 MX]
lappend P(MACRO_PLACE) {*}[qa_row [qa_act 2 1] $yB3 MX]
lappend P(MACRO_PLACE) {*}[qa_row [qa_w o 1 0] $yBw MX]
set P(MACRO_AUTO) 0
set ::QA_IO_Y0 [expr {$yB1 + $hA + $qa_halo}]
set ::QA_IO_Y1 [expr {$yT1 - $qa_halo}]
set ::QA_Y_BW $yBw
set ::QA_Y_TW_TOP [expr {$yTw + $hW}]
