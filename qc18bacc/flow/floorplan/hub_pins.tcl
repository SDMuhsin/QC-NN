# PIN_TCL of blocks/hub/hub.cfg (results/r9b.md, r10b.md): hub pins from <run>/pins9_data.tcl (floorplan/hub_pins.py),
# north edge only:
#   column south pins  fixed straight below the column pins (same layer / width / x)
#   act-port S-read pins u_top_s_q[*] (2048)  fixed on M6 at the north edge of the west strip, x = 24.1 + 0.4 k (on the
#                      M6 track grid 0.1 + 0.2 n; R43: 24 + 0.4 k was half a track off),
#                      k = 16 j + w for s_q[128 w + j] (j-major: the 16 words of bit j side by side, so each bit slice of the
#                      lane rotator is local); placed first: place_pins skips fixed pins
#   column north nets (t2, rst_n)  M8 pins under column c, evenly spaced, snapped to the M8 track grid 0.1 + 0.8 n (R43:
#                      the 0.4 grid put t2_s half a track off; no other pin uses M8; place_pins does not avoid
#                      the fixed column-south pins, r9b_d: GRT-0080 two pins at one position)
#   the other west-strip pins  place_pins on M3 / M5 + M2 / M4 (no layer shared with the fixed M6 pins), x 12 .. x0 - 12
source $::OUT/pins9_data.tcl
set _sq {}; set _w {}
foreach p $::QB9_WEST { if {[regexp {^u_top_s_q(?:\[(\d+)\]|_(\d+)_)$} $p - b1 b2]} { set b [expr {$b1 ne "" ? $b1 : $b2}] ; lappend _sq [list $p $b] } else { lappend _w $p } }
set ::QB9_WEST $_w
proc qb9_pins {} {
    set blk [ord::get_db_block]; set die [$blk getDieArea]
    set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set H [expr {[$die yMax] / double($u)}]
    clear_io_pin_constraints
    set n 0
    foreach r $::QB9_FIXED {
        lassign $r p ly x w h
        place_pin -pin_name $p -layer $ly -location [list $x [expr {$H - $h / 2.0}]] -pin_size [list $w $h]
        incr n
    }
    set x0 $::QB9_X0
    set_io_pin_constraint -pin_names $::QB9_WEST -region top:12-[expr {int($x0) - 12}]
    set nn 0
    foreach c [lsort -integer [array names ::QB9_NORTH]] {
        set l $::QB9_NORTH($c); set k 0; set step [expr {380.0 / max(1, [llength $l])}]
        foreach p $l {
            set x [expr {0.1 + round(($x0 + 390 * $c + 5 + ($k + 0.5) * $step - 0.1) / 0.8) * 0.8}]
            place_pin -pin_name $p -layer M8 -location [list $x [expr {$H - 0.4}]] -pin_size {0.4 0.8}
            incr k; incr nn
        }
    }
    place_pins -hor_layers {M3 M5} -ver_layers {M2 M4} -min_distance 2 -min_distance_in_tracks
    qc_log "r9b pins: fixed column-south $n, column-north $nn, west strip [llength $::QB9_WEST]"
}
set _H [expr {[[[ord::get_db_block] getDieArea] yMax] / double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set _x0 24.1
foreach e $_sq {
    lassign $e p b
    set k [expr {16 * ($b % 128) + $b / 128}]
    place_pin -pin_name $p -layer M6 -location [list [expr {$_x0 + 0.4 * $k}] [expr {$_H - 0.4}]] -pin_size {0.2 0.8}
}
qc_log "r10b pins: [llength $_sq] s_q pins fixed j-major on M6, x $_x0 .. [expr {$_x0 + 0.4 * ([llength $_sq] - 1)}]"
qb9_pins
