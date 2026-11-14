# IO pins of the column hard block qb_col_blk (PIN_TCL of impl/r5a/col.cfg; results/r5a.md):
#   west   act row r (288 b) inside PE row r's band (or the placed range of slice_repin: QB_PIN_Y(r)), M3 / M5
#   east   act_o: every act_o[b] at the y and on the layer of act[b] (abutment: column c's act_o meets column c+1's act)
#   north  cd, ctl, t2, clk, rst_n (codes, item controls, T2)
#   south  pf, pw, p_ld, w_ld (parameter loads), s_rd, w_r, f_y, f_b, w_y, w_b, f/w valids + PPU controls, b2, b2_vld (lane streams, b2 to the write-back)
# (body in a proc: no global variables leak into later steps, e.g. slice3_post_grt.tcl array w)
proc qb5_pins {} {
    global QB_PIN_Y QB5_DIR QB_DIR
    source $::QB_DIR/slice_bands.tcl
    qb_bands
    proc qb_ports {pat} {
        set l {}
        foreach b [[ord::get_db_block] getBTerms] { if {[string match $pat [$b getName]]} { lappend l [$b getName] } }
        return [lsort -dictionary $l]
    }
    set blk [ord::get_db_block]
    set die [$blk getDieArea]
    set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set W [expr {int([$die dx] / $u)}]
    # repin (second call): drop the constraints of the first placement (PPL-0098 otherwise)
    clear_io_pin_constraints
    set n 0
    for {set r 0} {$r < 16} {incr r} {
        set pins {}
        for {set b [expr {288 * $r}]} {$b < 288 * ($r + 1)} {incr b} { lappend pins "act\[$b\]" }
        lassign [qb_row_y $r] y0 y1
        if {[info exists ::QB_PIN_Y($r)]} { lassign $::QB_PIN_Y($r) y0 y1 }
        set_io_pin_constraint -pin_names $pins -region left:[expr {int($y0) + 1}]-[expr {int($y1) - 1}]
        incr n [llength $pins]
    }
    set_io_pin_constraint -pin_names [qb_ports "act_o\\\[*"] -region right:*
    # QB5_PFN 1: parameter loads pf / pw / p_ld / w_ld on the north edge (balances the two edges: 1 726 / 1 414 pins)
    set _pt {cd ctl t2 clk rst_n}; set _pb {pf pw p_ld w_ld s_rd f_y f_b w_r w_y w_b b2 b2_vld f_vld f_src f_sh w_vld w_sh f_vld_o w_vld_o}
    if {[qb_env QB5_PFN 0]} { set _pt [concat $_pt {pf pw p_ld w_ld}]; set _pb [lrange $_pb 4 end] }
    foreach {sd buses} [list top $_pt bottom $_pb] {
        set pins {}
        foreach bus $buses { set pins [concat $pins [qb_ports $bus] [qb_ports "${bus}\\\[*"]] }
        set_io_pin_constraint -pin_names $pins -region $sd:2-[expr {$W - 2}]
        qc_log "r5a pins: [llength $pins] on $sd"
        incr n [llength $pins]
    }
    # QB5_PIN_MD (tracks, default 2): with 1, place_pins packs the ~2 700 south pins over the lanes' x range (x 100-275 um)
    # and global route overflows at the south edge (GRT-0119, r5a_A / r5a_B try 1); 2 spreads them over the whole edge
    place_pins -hor_layers {M3 M5} -ver_layers [qb_env QB_VPIN_LAYERS {M2 M4 M6}] -min_distance [qb_env QB5_PIN_MD 2] -min_distance_in_tracks
    # act_o mirrors act: same layer, same y, same pin shape, on the east edge
    set t0 [clock seconds]; set m 0
    foreach bt [$blk getBTerms] {
        if {![regexp {^act\[(\d+)\]$} [$bt getName] -> b]} { continue }
        set bp [lindex [$bt getBPins] 0]; set bx [lindex [$bp getBoxes] 0]
        set ly [[$bx getTechLayer] getName]
        set w [expr {([$bx xMax] - [$bx xMin]) / double($u)}]; set h [expr {([$bx yMax] - [$bx yMin]) / double($u)}]
        set yc [expr {([$bx yMin] + [$bx yMax]) / 2.0 / $u}]
        set xc [expr {[$die xMax] / double($u) - ([$bx xMin] + [$bx xMax]) / 2.0 / $u + [$die xMin] / double($u)}]
        place_pin -pin_name "act_o\[$b\]" -layer $ly -location [list $xc $yc] -pin_size [list $w $h]
        incr m
    }
    qc_log "r5a pins: $n placed by place_pins + $m act_o mirrored ([expr {[clock seconds] - $t0}] s)"
}
qb5_pins
