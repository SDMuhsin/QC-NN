# PRE_PLACE_TCL of core.cfg: IO pins placed after a skip-IO global placement (as ORFS: global_place_skip_io ->
# io_placement -> global_place), on fixed sides, positions within a side chosen by place_pins near their logic.
# Why: with the floorplan-time ordered bus groups of pins.tcl (pf bottom, lane stream right), each fused lane was
# stretched between its parameter pins and its stream pins (qbs_p1 place: lane u_rlate (691, 151) -> u_rout
# (1226, 617) um, 37-buffer wire chain, tt -1.26 ns), an artefact of the standalone block (in the top the parameter
# bank and the stream macros feed the lanes from one side).  Sides here:
#   left  = array side (act, cd, ctl, t2, clk, rst_n)      top = b2, b2_vld
#   right = every lane-side bus (pf, pw, s_rd, w_r, f_y, f_b, w_y, w_b, PPU controls, valids), 3 layers M3 M5 M7
# Then gpl_incr.tcl (incremental gpl + second DRV repair after the place step's repair).
set gpl [list -skip_io -density [p PLACE_DENSITY] -pad_left [p PLACE_PAD] -pad_right [p PLACE_PAD] {*}[p GPL_ARGS]]
qc_log "io_place: skip-io global placement"
global_placement {*}$gpl
proc qb_ports {pat} {
    set l {}
    foreach b [[ord::get_db_block] getBTerms] { if {[string match $pat [$b getName]]} { lappend l [$b getName] } }
    return $l
}
set die [[ord::get_db_block] getDieArea]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set W [expr {int([$die dx] / $u)}]; set H [expr {int([$die dy] / $u)}]
array set qb_side {
    left   {act cd ctl t2 clk rst_n}
    top    {b2 b2_vld}
    right  {pf pw s_rd w_r f_y f_b w_y w_b f_vld f_src f_sh p_ld w_vld w_sh w_ld f_vld_o w_vld_o}
}
foreach sd {left top right} {
    set pins {}
    foreach bus $qb_side($sd) { set pins [concat $pins [qb_ports $bus] [qb_ports "${bus}\\\[*"]] }
    set len [expr {$sd in {left right} ? $H : $W}]
    set_io_pin_constraint -pin_names $pins -region $sd:5-[expr {$len - 5}]
    qc_log "io_place: [llength $pins] pins on $sd"
}
place_pins -hor_layers {M3 M5 M7} -ver_layers {M4 M6} -min_distance 1 -min_distance_in_tracks
qc_log "io_place: pins placed"
source [file dirname [p PIN_TCL]]/gpl_incr.tcl
