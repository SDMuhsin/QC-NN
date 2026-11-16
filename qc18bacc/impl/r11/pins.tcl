# PIN_TCL of impl/r11/top.cfg: chip IO pins on the west edge of the NW corner (sequencer / host registers), y range
# ::QB11_IOY of <run>/mplace.tcl (fp11.py), M3 / M5; QB11_IOGAP 1: west edge of the hub-to-act gap.
clear_io_pin_constraints
lassign $::QB11_IOY _y0 _y1
# QB11_IOGAP 1: chip IOs (host port) on the west edge of the hub-to-act gap instead (next to the hub's west-strip pins)
if {[qb_env QB11_IOGAP 0]} { set _y0 [expr {$::QB11_YH + 20}]; set _y1 [expr {[lindex $::QB11_ACT 1] - 20}] }
set_io_pin_constraint -region left:[expr {int($_y0)}]-[expr {int($_y1)}] -pin_names [lmap b [[ord::get_db_block] getBTerms] {$b getName}]
place_pins -hor_layers {M3 M5} -ver_layers {M2 M4} -min_distance 2 -min_distance_in_tracks
qc_log "r11 pins: [llength [[ord::get_db_block] getBTerms]] chip IO pins west edge y $_y0 .. $_y1"
