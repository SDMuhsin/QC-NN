# PIN_TCL of impl/r9b/hub.cfg: hub pins from <run>/pins9_data.tcl (impl/r9b/pins9.py), north edge only
source $::OUT/pins9_data.tcl
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
    # column-north nets (t2, rst_n): M8 pins under column c, evenly spaced (no other pin uses M8; place_pins does not
    # avoid the fixed column-south pins, r9b_d: GRT-0080 two pins at one position)
    set nn 0
    foreach c [lsort -integer [array names ::QB9_NORTH]] {
        set l $::QB9_NORTH($c); set k 0; set step [expr {380.0 / max(1, [llength $l])}]
        foreach p $l {
            set x [expr {round(($x0 + 390 * $c + 5 + ($k + 0.5) * $step) / 0.4) * 0.4}]
            place_pin -pin_name $p -layer M8 -location [list $x [expr {$H - 0.4}]] -pin_size {0.4 0.8}
            incr k; incr nn
        }
    }
    place_pins -hor_layers {M3 M5} -ver_layers [qb_env QB9_PIN_VL {M2 M4 M6}] -min_distance [qb_env QB9_PIN_MD 2] -min_distance_in_tracks
    qc_log "r9b pins: fixed column-south $n, column-north $nn, west strip [llength $::QB9_WEST]"
}
qb9_pins
