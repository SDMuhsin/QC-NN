# IO pins of qb_core (PIN_TCL of core.cfg).  Each bus in bit order, as ordered groups of <= 512 pins (one group must
# fit a pin section; act row r = 288 bits, so the 16 PE rows line up along the left edge):  left = array side (act,
# cd, ctl, t2, clk, rst_n), top = b2 / b2_vld + wide parameter bank pw, bottom = fused parameter bank pf, right =
# lane stream (s_rd, w_r, f_y, f_b, w_y, w_b, PPU controls, valids).  ~29.5 k signal pins on a ~3 mm square core:
# two layers per edge (M3 + M5 left / right, M4 + M6 top / bottom; one layer at the 2-track pin pitch of place_pins
# holds ~7.4 k pins per edge, the left edge needs 8.0 k).
proc qb_ports {pat} {
    set l {}
    foreach b [[ord::get_db_block] getBTerms] { if {[string match $pat [$b getName]]} { lappend l [$b getName] } }
    return [lsort -dictionary $l]
}
set die [[ord::get_db_block] getDieArea]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set W [expr {int([$die dx] / $u)}]; set H [expr {int([$die dy] / $u)}]
array set side {
    left   {act cd ctl t2 clk rst_n}
    top    {b2 b2_vld pw}
    bottom {pf}
    right  {s_rd w_r f_y f_b w_y w_b f_vld f_src f_sh p_ld w_vld w_sh w_ld f_vld_o w_vld_o}
}
set n 0
foreach sd {left top bottom right} {
    set pins {}
    foreach bus $side($sd) {
        set l [concat [qb_ports $bus] [qb_ports "${bus}\\\[*"]]
        for {set i 0} {$i < [llength $l]} {incr i 512} {
            set g [lrange $l $i [expr {$i + 511}]]
            if {[llength $g] > 1} { set_io_pin_constraint -group -order -pin_names $g }
        }
        set pins [concat $pins $l]
    }
    set len [expr {$sd in {left right} ? $H : $W}]
    set_io_pin_constraint -pin_names $pins -region $sd:5-[expr {$len - 5}]
    qc_log "io pins: [llength $pins] on $sd"
    incr n [llength $pins]
}
qc_log "io pins total $n"
place_pins -hor_layers {M3 M5} -ver_layers {M4 M6} -min_distance 1 -min_distance_in_tracks
