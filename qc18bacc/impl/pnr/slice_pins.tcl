# IO pins of qb_col (PIN_TCL of slice.cfg), on the abutment edges of the strip (results/pnr_slice.md):
#   left   act row r (288 b) + b2 row r (8 b), each within PE row r's band (slice_bands.tcl), ordered by bit
#   top    cd, ctl, t2, clk, rst_n, b2_vld (codes broadcast down the column)
#   bottom lane stream (s_rd, f_y, f_b, w_r, w_y, w_b), parameter banks (pf, pw), PPU controls and valids
#          (the S macros / parameter store sit below the lane band)
source $::QB_DIR/slice_bands.tcl
qb_bands
proc qb_ports {pat} {
    set l {}
    foreach b [[ord::get_db_block] getBTerms] { if {[string match $pat [$b getName]]} { lappend l [$b getName] } }
    return [lsort -dictionary $l]
}
set die [[ord::get_db_block] getDieArea]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set W [expr {int([$die dx] / $u)}]; set H [expr {int([$die dy] / $u)}]
set n 0
for {set r 0} {$r < 16} {incr r} {
    set pins {}
    for {set b [expr {288 * $r}]} {$b < 288 * ($r + 1)} {incr b} { lappend pins "act\[$b\]" }
    for {set b [expr {8 * $r}]} {$b < 8 * ($r + 1)} {incr b} { lappend pins "b2\[$b\]" }
    lassign [qb_row_y $r] y0 y1
    if {[info exists ::QB_PIN_Y($r)]} { lassign $::QB_PIN_Y($r) y0 y1 }    ;# slice_repin.tcl: placed PE row r
    set_io_pin_constraint -pin_names $pins -region left:[expr {int($y0) + 1}]-[expr {int($y1) - 1}]
    incr n [llength $pins]
}
qc_log "slice pins: $n on left (16 row groups)"
foreach {sd buses} {
    top    {cd ctl t2 clk rst_n b2_vld}
    bottom {s_rd f_y f_b w_r w_y w_b pf pw f_vld f_src f_sh p_ld w_vld w_sh w_ld f_vld_o w_vld_o}
} {
    set pins {}
    foreach bus $buses { set pins [concat $pins [qb_ports $bus] [qb_ports "${bus}\\\[*"]] }
    set_io_pin_constraint -pin_names $pins -region $sd:2-[expr {$W - 2}]
    qc_log "slice pins: [llength $pins] on $sd"
    incr n [llength $pins]
}
qc_log "slice pins total $n"
place_pins -hor_layers {M3 M5} -ver_layers {M4 M6} -min_distance 1 -min_distance_in_tracks
