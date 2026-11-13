# PIN_TCL of impl/hard/pe.cfg: block pins of qb_pe_hb on the sides of their neighbours in the column floorplan
# (impl/hard/col.cfg): west act a + b2 (column act / b2 pins), east BR outputs + drain shifts + clock / reset
# (spine with the decoders and broadcast registers), north up / sh_in (PE r + 4 above), south shd / sh_out (PE r - 4
# or the lanes below).  Each bus in bit order over the middle 90 % of its edge.
proc qb_bus {pats} {
    set l {}
    foreach p $pats {
        set b {}
        foreach t [[ord::get_db_block] getBTerms] { if {[regexp "^${p}(\\\[\\d+\\\])?\$" [$t getName]]} { lappend b [$t getName] } }
        set l [concat $l [lsort -dictionary $b]]
    }
    return $l
}
set die [[ord::get_db_block] getDieArea]
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set W [expr {[$die dx] / double($u)}]; set H [expr {[$die dy] / double($u)}]
set a0 [expr {int(0.05 * $H)}]; set a1 [expr {int(0.95 * $H)}]
set b0 [expr {int(0.05 * $W)}]; set b1 [expr {int(0.95 * $W)}]
foreach {sd pats lo hi} [list \
        left   {a b2}                                            $a0 $a1 \
        right  {c nnw ctl t2 fsh wsh clk rst_n}                  $a0 $a1 \
        top    {up sh_in}                                        $b0 $b1 \
        bottom {shd sh_out}                                      $b0 $b1] {
    set pins [qb_bus $pats]
    set_io_pin_constraint -pin_names $pins -region $sd:$lo-$hi
    qc_log "pe pins: [llength $pins] on $sd ($lo-$hi um)"
}
place_pins -hor_layers {M3 M5} -ver_layers {M4 M6} -min_distance 1 -min_distance_in_tracks
