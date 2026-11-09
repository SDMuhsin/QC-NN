# IO pins of QC18-ACC (PIN_TCL): host port on the left edge of the logic band (QA_IO_Y0 / Y1 from macro_place.tcl),
# each bus contiguous and in bit order; clk, rst_n, busy, done with it.
proc qa_ports {pat} {
    set l {}
    foreach b [[ord::get_db_block] getBTerms] { if {[string match $pat [$b getName]]} { lappend l [$b getName] } }
    return [lsort -dictionary $l]
}
set y0 [expr {int($::QA_IO_Y0) + 5}]; set y1 [expr {int($::QA_IO_Y1) - 5}]
foreach bus {host_addr host_wdata host_rdata} { set_io_pin_constraint -group -order -pin_names [qa_ports "${bus}\\\[*"] }
set all {}
foreach b [[ord::get_db_block] getBTerms] { if {[$b getSigType] ni {POWER GROUND}} { lappend all [$b getName] } }
set_io_pin_constraint -pin_names $all -region left:$y0-$y1
qc_log "io pins: [llength $all] on the left edge, y $y0-$y1"
place_pins -hor_layers $::QC_PNR_PIN_H -ver_layers $::QC_PNR_PIN_V -min_distance 2 -min_distance_in_tracks \
    -exclude top:* -exclude bottom:* -exclude right:* -exclude left:0-$y0 -exclude left:$y1-$::QA_DIE_H
