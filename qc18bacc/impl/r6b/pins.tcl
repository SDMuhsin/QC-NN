# PIN_TCL of impl/r6b/chip.cfg: all chip IOs (narrow host port, clk / rst, logits; 220) on the west die edge in the
# W group's y range (::QB_PIN_Y from mplace.tcl), next to the IO register stage of qb_chip.
set _names {}
foreach bt [[ord::get_db_block] getBTerms] {
    if {[$bt getSigType] in {POWER GROUND}} continue
    lappend _names [$bt getName]
}
lassign $::QB_PIN_Y _y1 _y2
set_io_pin_constraint -pin_names $_names -region left:$_y1-$_y2
place_pins -hor_layers $::QC_PNR_PIN_H -ver_layers $::QC_PNR_PIN_V -min_distance 2 -min_distance_in_tracks
qc_log "pins: [llength $_names] on the west edge y $_y1-$_y2"
