# PIN_TCL of blocks/act/act.cfg (results/r13.md; floorplan of R11: act block at the array top, sequencer in the west-strip
# gap below it, hub below that):
#   east   act[b] at column 0's act pins (pin table QB7_COLPINS, block y = column y - QB7_YOFF [3110 - die height])
#   south  everything else: s_q / m_q read data, read ports, clk / rst_n, controls, tokens, flags, descriptors (none north)
#   s_q    fixed on M6 at the south edge in the hub's physical order (hub s_q[m] at x = x0 + 0.4 k, k = 16 (m % 128) + m / 128,
#          j-major) seen through the WB_COL transpose T (hw/rtl/qb_act2.sv s_qt): this block has no WB_COL, its s_q[n] is the
#          logical word = s_qt[n] = hub s_q[m] with n = 128 (4G + b) + 32 q + 8 a + i, m = 128 (4G + a) + 32 b + 8 q + i, so
#          block pin n sits at the x of hub pin m (x0 = 64 = hub x 40 + 24, r35.md): every block-to-hub s_q wire is vertical.
#   other south pins by place_pins on M2 / M4 / M3 / M5 (no M6: the fixed s_q pins), min distance 2 tracks; m_q has no fixed
#          hub order (the hub's m_q pins are place_pins too), so it is left to place_pins.
proc qb13_pins {} {
    set blk [ord::get_db_block]; set die [$blk getDieArea]
    set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set W [expr {[$die dx] / double($u)}]; set H [expr {[$die dy] / double($u)}]
    set yoff [qb_env QB7_YOFF [expr {3110.0 - $H}]]
    set x0 64
    clear_io_pin_constraints
    set A {}; set C {}; set Q {}
    foreach b [$blk getBTerms] {
        set n [$b getName]
        if {[$b getSigType] ne "SIGNAL" && $n ne "clk"} { continue }
        if {[regexp {^act\[} $n]} { lappend A $n } elseif {[regexp {^s_q\[(\d+)\]$} $n - k]} { lappend Q [list $n $k] } else { lappend C $n }
    }
    set xmax 0
    foreach e $Q {
        lassign $e p n
        set G [expr {$n / 512}]; set b [expr {($n / 128) % 4}]; set q [expr {($n / 32) % 4}]; set a [expr {($n / 8) % 4}]; set i [expr {$n % 8}]
        set m [expr {128 * (4 * $G + $a) + 32 * $b + 8 * $q + $i}]
        set k [expr {16 * ($m % 128) + $m / 128}]
        set x [expr {$x0 + 0.4 * $k}]; if {$x > $xmax} { set xmax $x }
        place_pin -pin_name $p -layer M6 -location [list $x 0.4] -pin_size {0.2 0.8}
    }
    set_io_pin_constraint -pin_names $C -region bottom:2-[expr {int($W) - 2}]
    set_io_pin_constraint -pin_names $A -region right:*
    place_pins -hor_layers {M3 M5} -ver_layers {M2 M4} -min_distance 2 -min_distance_in_tracks
    set f [open [qb_env QB7_COLPINS $::QC_BUILD/col_act_pins.txt]]; set mm 0
    foreach line [split [read $f] \n] {
        if {[llength $line] < 6} { continue }
        lassign $line b ly xa ya xb yb
        set y [expr {($ya + $yb) / 2.0 - $yoff}]; set w [expr {$xb - $xa}]; set h [expr {$yb - $ya}]
        place_pin -pin_name "act\[$b\]" -layer $ly -location [list [expr {$W - $w / 2.0}] $y] -pin_size [list $w $h]
        incr mm
    }
    close $f
    qc_summary "r13 pins: $mm act east at column 0 y (yoff $yoff); south: [llength $Q] s_q fixed M6 hub order x $x0 .. $xmax, [llength $C] other (place_pins M2-M5)"
}
qb13_pins
