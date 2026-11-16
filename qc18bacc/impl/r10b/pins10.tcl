# PIN_TCL of impl/r10b/hub.cfg: impl/r9b/pins9.tcl, except the 2048 act-port S-read pins u_top_s_q[*] (QB10_SQPIN 1):
# fixed on M6 at the north edge of the west strip, x = QB10_SQX0 [24] + 0.4 k, k = 16 j + w for s_q[128 w + j]
# (j-major: the 16 words of bit j side by side, so each bit slice of the lane rotator is local); the other west-strip
# pins by place_pins on M2 / M4 (s_q placed first: place_pins skips fixed pins) (QB9_PIN_VL), no shared layer with the fixed M6 pins.
source $::OUT/pins9_data.tcl
if {[qb_env QB10_SQPIN 1]} {
    set _sq {}; set _w {}
    foreach p $::QB9_WEST { if {[regexp {^u_top_s_q(?:\[(\d+)\]|_(\d+)_)$} $p - b1 b2]} { set b [expr {$b1 ne "" ? $b1 : $b2}] ; lappend _sq [list $p $b] } else { lappend _w $p } }
    set ::QB9_WEST $_w
    set ::env(QB9_PIN_VL) [qb_env QB9_PIN_VL {M2 M4}]
}
set _f [open $::QB_R9B/pins9.tcl]; set _t [read $_f]; close $_f
# reuse pins9.tcl without its data source line and without its final call
regsub {source \$::OUT/pins9_data.tcl\n} $_t {} _t
regsub {\nqb9_pins\s*$} $_t "\n" _t
eval $_t
if {[qb_env QB10_SQPIN 1]} {
    set _H [expr {[[[ord::get_db_block] getDieArea] yMax] / double([[ord::get_db_tech] getDbUnitsPerMicron])}]
    set _x0 [qb_env QB10_SQX0 24]
    foreach e $_sq {
        lassign $e p b
        set k [expr {16 * ($b % 128) + $b / 128}]
        place_pin -pin_name $p -layer M6 -location [list [expr {$_x0 + 0.4 * $k}] [expr {$_H - 0.4}]] -pin_size {0.2 0.8}
    }
    qc_log "r10b pins: [llength $_sq] s_q pins fixed j-major on M6, x $_x0 .. [expr {$_x0 + 0.4 * ([llength $_sq] - 1)}]"
}
qb9_pins
