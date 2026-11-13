# PIN_TCL of impl/hard/col.cfg: act / b2 of row r on the die edge next to PE r (west even rows, east odd rows),
# middle 90 % of the block's y range; codes / ctl / t2 / clk / rst_n / b2_vld on top over the spine (+- 60 um);
# lane stream, banks and PPU controls along the bottom.  Logs the placed macro boxes (orientation check).
set blk [ord::get_db_block]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
foreach i [$blk getInsts] {
    if {[[$i getMaster] isBlock]} {
        set b [$i getBBox]
        qc_log [format "macro %s %s bbox %.1f %.1f %.1f %.1f" [$i getName] [$i getOrient] [expr {[$b xMin] / double($u)}] \
            [expr {[$b yMin] / double($u)}] [expr {[$b xMax] / double($u)}] [expr {[$b yMax] / double($u)}]]
    }
}
proc qb_ports {pat} {
    set l {}
    foreach b [[ord::get_db_block] getBTerms] { if {[regexp "^${pat}(\\\[\\d+\\\])?\$" [$b getName]]} { lappend l [$b getName] } }
    return [lsort -dictionary $l]
}
set die [$blk getDieArea]
set W [expr {[$die dx] / double($u)}]
set n 0
for {set r 0} {$r < 16} {incr r} {
    set pins {}
    for {set b [expr {288 * $r}]} {$b < 288 * ($r + 1)} {incr b} { lappend pins "act\[$b\]" }
    for {set b [expr {8 * $r}]} {$b < 8 * ($r + 1)} {incr b} { lappend pins "b2\[$b\]" }
    set y0 [qb_lvl_y [expr {$r / 2}]]
    set_io_pin_constraint -pin_names $pins -region [expr {$r % 2 ? "right" : "left"}]:[expr {int($y0 + 0.05 * $::QB_B)}]-[expr {int($y0 + 0.95 * $::QB_B)}]
    incr n [llength $pins]
}
set xc [expr {$::QB_XS + $::QB_S / 2.0}]
foreach {sd buses lo hi} [list \
    top    {cd ctl t2 clk rst_n b2_vld} [expr {int($xc - 60)}] [expr {int($xc + 60)}] \
    bottom {s_rd f_y f_b w_r w_y w_b pf pw f_vld f_src f_sh p_ld w_vld w_sh w_ld f_vld_o w_vld_o} 2 [expr {int($W - 2)}]] {
    set pins {}
    foreach bus $buses { set pins [concat $pins [qb_ports $bus]] }
    set_io_pin_constraint -pin_names $pins -region $sd:$lo-$hi
    qc_log "col pins: [llength $pins] on $sd"
    incr n [llength $pins]
}
qc_log "col pins total $n"
place_pins -hor_layers {M3 M5} -ver_layers {M4 M6} -min_distance 1 -min_distance_in_tracks
