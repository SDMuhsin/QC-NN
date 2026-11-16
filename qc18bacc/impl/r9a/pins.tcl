# IO pins of the R9a act-supply hard block qb_act2_blk (PIN_TCL of impl/r9a/act.cfg; results/r9a.md):
#   east   act[b] at exactly the layer, shape and y of column 0's act[b] (QB7_COLPINS table of impl/r7c/col_pins.py),
#          shifted by QB7_YOFF = chip y of this block's origin - chip y of the column origin (default: block top = array
#          top, 3110 - die height); abutment at the shared x edge
#   south  the S / map read port: s_q (2 048) + m_q (512) data and s_ren / s_ra / s_ctx / m_ren / m_ra / m_ctx
#          (the S and map macros sit in the chip's south band), M2 / M4 / M6, >= QB7_PIN_MD tracks apart
#   north  (QB9_CTL_SIDE top; bottom = with the S port) clk, rst_n and every other port: pass commands, tokens, load
#          permissions, flag port, busy / done / l_pos, descriptors d_* / a_*, err (sequencer / glue)
proc qb9_pins {} {
    set blk [ord::get_db_block]; set die [$blk getDieArea]
    set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set W [expr {[$die dx] / double($u)}]; set H [expr {[$die dy] / double($u)}]
    set yoff [qb_env QB7_YOFF [expr {3110.0 - $H}]]
    clear_io_pin_constraints
    set S {}; set A {}; set C {}
    foreach b [$blk getBTerms] {
        set n [$b getName]
        if {[$b getSigType] ne "SIGNAL" && $n ne "clk"} { continue }
        if {[regexp {^act\[} $n]} { lappend A $n } elseif {[regexp {^(s_q|m_q|s_ra|m_ra)\[|^(s_ren|m_ren|s_ctx|m_ctx)$} $n]} {
            lappend S $n } else { lappend C $n }
    }
    set cs [qb_env QB9_CTL_SIDE top]
    set_io_pin_constraint -pin_names $S -region bottom:2-[expr {int($W) - 2}]
    set_io_pin_constraint -pin_names $C -region $cs:[expr {int($W) / 2 - 150}]-[expr {int($W) / 2 + 150}]
    set_io_pin_constraint -pin_names $A -region right:*
    qc_log "r9a pins: south (S / map read port) [llength $S] $cs (controls) [llength $C] east (act) [llength $A]"
    place_pins -hor_layers {M3 M5} -ver_layers {M2 M4 M6} -min_distance [qb_env QB7_PIN_MD 2] -min_distance_in_tracks
    set f [open [qb_env QB7_COLPINS $::QC_BUILD/col_act_pins.txt]]; set m 0; set out 0
    foreach line [split [read $f] \n] {
        if {[llength $line] < 6} { continue }
        lassign $line b ly x0 y0 x1 y1
        set y [expr {($y0 + $y1) / 2.0 - $yoff}]; set w [expr {$x1 - $x0}]; set h [expr {$y1 - $y0}]
        if {$y < $h + 5.0 || $y > $H - $h - 5.0} { incr out }
        place_pin -pin_name "act\[$b\]" -layer $ly -location [list [expr {$W - $w / 2.0}] $y] -pin_size [list $w $h]
        incr m
    }
    close $f
    qc_summary "r9a pins: $m act pins at column 0 y (yoff $yoff um, outside the core $out); south [llength $S]; $cs [llength $C]"
}
qb9_pins
