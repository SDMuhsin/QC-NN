# PIN_TCL of blocks/top/top.cfg (results/r11.md, r14.md): chip IO pins (host port) on the west edge of the hub-to-act gap
# (next to the hub's west-strip pins), y from ::QB11_YH + 20 to the act bottom - 20 (<run>/mplace.tcl,
# floorplan/top_fp.py), M3 / M5.
clear_io_pin_constraints
set _y0 [expr {$::QB11_YH + 20}]; set _y1 [expr {[lindex $::QB11_ACT 1] - 20}]
set_io_pin_constraint -region left:[expr {int($_y0)}]-[expr {int($_y1)}] -pin_names [lmap b [[ord::get_db_block] getBTerms] {$b getName}]
place_pins -hor_layers {M3 M5} -ver_layers {M2 M4} -min_distance 2 -min_distance_in_tracks
qc_log "r11 pins: [llength [[ord::get_db_block] getBTerms]] chip IO pins west edge y $_y0 .. $_y1"
