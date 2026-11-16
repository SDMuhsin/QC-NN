# IO pins of the act-supply hard block qb_act2_blk (PIN_TCL of impl/r7c/act.cfg; results/r7c.md):
#   east   act[b] at exactly the layer, shape and y of column 0's act[b] (table QB7_COLPINS from col_pins.py of the
#          column block LEF), shifted by QB7_YOFF = chip y of this block's origin - chip y of the column origin
#          (default: block top = array top, i.e. 3110 - die height); abutment at the shared x edge
#   south  s_q (S read) / m_q (map read) on M2 / M4 / M6, spread over the edge (QB7_PIN_MD tracks apart)
#   west   clk, rst_n, every other input / output (pass commands, tokens, load permissions, flag port, read ports,
#          descriptors, busy / done / l_pos, err)
proc qb7_pins {} {
    set blk [ord::get_db_block]; set die [$blk getDieArea]
    set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set W [expr {[$die dx] / double($u)}]; set H [expr {[$die dy] / double($u)}]
    set yoff [qb_env QB7_YOFF [expr {3110.0 - $H}]]
    clear_io_pin_constraints
    set S {}; set A {}; set Wp {}
    foreach b [$blk getBTerms] {
        set n [$b getName]
        if {[$b getSigType] ne "SIGNAL"} { continue }
        if {[regexp {^act\[} $n]} { lappend A $n } elseif {[regexp {^(s_q|m_q)\[} $n]} { lappend S $n } else { lappend Wp $n }
    }
    set_io_pin_constraint -pin_names $S -region bottom:2-[expr {int($W) - 2}]
    set_io_pin_constraint -pin_names $Wp -region left:2-[expr {int($H) - 2}]
    set_io_pin_constraint -pin_names $A -region right:*
    qc_log "r7c pins: south [llength $S] west [llength $Wp] east (act) [llength $A]"
    place_pins -hor_layers {M3 M5} -ver_layers {M2 M4 M6} -min_distance [qb_env QB7_PIN_MD 2] -min_distance_in_tracks
    # act: column 0's pins mirrored onto this block's east edge
    set f [open [qb_env QB7_COLPINS $::QC_BUILD/col_act_pins.txt]]; set m 0; set out 0
    foreach line [split [read $f] \n] {
        if {[llength $line] < 6} { continue }
        lassign $line b ly x0 y0 x1 y1
        set y [expr {($y0 + $y1) / 2.0 - $yoff}]; set w [expr {$x1 - $x0}]; set h [expr {$y1 - $y0}]
        if {$y < $h || $y > $H - $h} { incr out }
        place_pin -pin_name "act\[$b\]" -layer $ly -location [list [expr {$W - $w / 2.0}] $y] -pin_size [list $w $h]
        incr m
    }
    close $f
    qc_log "r7c pins: $m act pins at column 0 y (yoff $yoff um, outside the die $out)"
}
qb7_pins
