# IO pins of the KUL cluster (PIN_TCL): left and right edges of the logic band between the macro banks
# (KUL_IO_Y0 / Y1 from macro_place.tcl), each bus contiguous and in bit order.
# left: AXI slave side (narrow_in_*, wide_in_*), clock, reset, interrupts, static config; right: AXI masters.
proc kul_ports {pat} {
    set l {}
    foreach b [[ord::get_db_block] getBTerms] { if {[string match $pat [$b getName]]} { lappend l [$b getName] } }
    return [lsort -dictionary $l]
}
set y0 [expr {int($::KUL_IO_Y0) + 5}]; set y1 [expr {int($::KUL_IO_Y1) - 5}]
set left {}; set right {}
foreach bus {narrow_in_req_i narrow_in_resp_o wide_in_req_i wide_in_resp_o} {
    set p [kul_ports "${bus}\\\[*"]; lappend left {*}$p
    set_io_pin_constraint -group -order -pin_names $p
}
foreach bus {narrow_out_req_o narrow_out_resp_i wide_out_req_o wide_out_resp_i} {
    set p [kul_ports "${bus}\\\[*"]; lappend right {*}$p
    set_io_pin_constraint -group -order -pin_names $p
}
set misc {}
foreach b [[ord::get_db_block] getBTerms] {
    set n [$b getName]
    if {[lsearch -exact $left $n] < 0 && [lsearch -exact $right $n] < 0 && [$b getSigType] ni {POWER GROUND}} { lappend misc $n }
}
set_io_pin_constraint -pin_names [concat $left $misc] -region left:$y0-$y1
set_io_pin_constraint -pin_names $right -region right:$y0-$y1
qc_log "io pins: left [llength $left] + [llength $misc] misc, right [llength $right], y $y0-$y1"
place_pins -hor_layers $::QC_PNR_PIN_H -ver_layers $::QC_PNR_PIN_V -min_distance 2 -min_distance_in_tracks \
    -exclude top:* -exclude bottom:* -exclude left:0-$y0 -exclude left:$y1-$::KUL_DIE_H -exclude right:0-$y0 -exclude right:$y1-$::KUL_DIE_H
