# IO budget of the column hard block qb_col_blk (results/r5a.md) for the R5b top, as fractions of the period P.
# Delays are relative to the clock at the top-level flops; the top-level tree is balanced with the block's internal
# sinks, so after CTS (P&R post-CTS, PrimeTime) they are shifted by the block insertion delay L: inputs + L, outputs - L.
#   act (west, 16 x 288)   max 0.55 P: launch flop + top wire (0.06 P) + 7 upstream feedthroughs (7 x 0.07 P) = column 7
#   act_o (east)           output 0.38 P - U = P - 0.55 P - 0.07 P - U: feedthrough act -> act_o <= 0.07 P per column
#                          (U = setup uncertainty QC_UNC_SETUP 0.25 ns, counted once on the top-level flop -> flop path)
#   north inputs           cd / ctl / t2 (codes, item controls, T2): 0.30 P
#   south inputs           pf / pw / p_ld / w_ld (parameter loads), s_rd / w_r (stream reads), f_vld / f_src / f_sh /
#                          w_vld / w_sh (PPU controls): QB5_SOUTH_IN (default 0.20 P, as the column / slice runs)
#   south outputs          f_y / f_b / w_y / w_b / *_vld_o (lane results), b2 / b2_vld: 0.25 P
#   min (hold) input delay 0.05 P everywhere (column 0 act, near flops); output min 0
#   act_o load             qb5_act_o_load: column c's act_o[b] drives column c+1's act[b] (abutment: same bit, same y, an
#                          identical block), so act_o[b] gets the capacitance of this block's own act[b] net, per bit
#                          (pins + wire of the current timing state).  Per bit, not the max over the bits: the load of
#                          bit b is exactly that of the same net in the next column (R63 [M] ss ETM act pins p50 0.037,
#                          max 0.088 pF), so the max would over-load most of the 4608 feedthroughs ~2x.  It replaces the
#                          common 4 x INVD4 (constraints.sdc, 0.0187 pF), which is not what an abutted act_o drives.
#   act driving cell       qb5_act_drv: column c's act[b] is driven by column c-1's act_o[b] driver, the same netlist
#                          cell (and size) as this block's own act_o[b] driver, so act[b] gets that lib cell / pin as its
#                          driving cell, per bit (R67: the common BUFFD4 of constraints.sdc was stronger than 3447 of the
#                          4608 feedthroughs).  Measured on the current netlist (ICC2 sizes the size_only feedthroughs).
proc qb5_budget {} {
    set si [expr {[info exists ::env(QB5_SOUTH_IN)] ? $::env(QB5_SOUTH_IN) : 0.20}]
    return [subst -nocommands {
        in  {act[*]}                                   0.55 0.05
        in  {cd[*] ctl[*] t2[*]}                       0.30 0.05
        in  {pf[*] pw[*] p_ld w_ld s_rd[*] w_r[*] f_vld f_src f_sh w_vld w_sh} $si 0.05
        out {act_o[*]}                                 0.38 0.0
        out {f_y[*] f_b[*] w_y[*] w_b[*] f_vld_o w_vld_o b2[*] b2_vld} 0.25 0.0
    }]
}
# SDC lines of the budget at period per, shifted by the insertion delay L (0 for ideal clocks)
proc qb5_io_lines {per {L 0.0}} {
    set out {}
    set U [expr {[info exists ::env(QC_UNC_SETUP)] ? $::env(QC_UNC_SETUP) : 0.25}]
    foreach {d pats mx mn} [qb5_budget] {
        set s [expr {$d eq "in" ? $L : -$L}]
        set su [expr {[string match act_o* $pats] ? $U : 0.0}]
        set cmd [expr {$d eq "in" ? "set_input_delay" : "set_output_delay"}]
        lappend out [format "%s -max %.4f -clock qb_clk \[get_ports {%s}\]" $cmd [expr {$mx * $per + $s - $su}] $pats]
        lappend out [format "%s -min %.4f -clock qb_clk \[get_ports {%s}\]" $cmd [expr {$mn * $per + $s}] $pats]
    }
    return [join $out "\n"]
}
proc qb5_io_apply {per {L 0.0}} { foreach l [split [qb5_io_lines $per $L] "\n"] { uplevel #0 $l } }
# act_o[b] load = capacitance of the act[b] net.  qb5_act_o_caps <capof>: {b cap ...} of every act[b], capof = command
# prefix called with the act port, returning that net's capacitance in the tool's current timing state; qb5_act_o_load
# <caps>: set_load of each act_o[b].  Separate, because a set_load invalidates the timing (ICC2 also clears the net
# parasitics, TIM-123: R64 [M] reading on after it gave empty / 0 caps), so every corner is measured before the first
# set_load (PrimeTime signoff/pt/col_blk.tcl, ICC2 flow/icc2 qb_io_load).
proc qb5_act_o_caps {capof} {
    set ld {}
    foreach_in_collection p [get_ports {act[*]}] {
        regexp {\[(\d+)\]$} [get_object_name $p] -> b
        set c [{*}$capof $p]
        if {![string is double -strict $c] || $c <= 0} { error "qb5_act_o_caps: no capacitance on [get_object_name $p] ($c)" }
        lappend ld $b $c
    }
    return $ld
}
proc qb5_act_o_load {ld} {
    set v {}
    foreach {b c} $ld { set_load $c [get_ports "act_o\[$b\]"]; lappend v $c }
    set v [lsort -real $v]; set n [llength $v]
    puts [format "QB5_ACT_O_LOAD %d act_o ports, per-bit load = own act net: min %.4f p50 %.4f max %.4f pF" $n \
        [lindex $v 0] [lindex $v [expr {$n / 2}]] [lindex $v end]]
}
# act[b] driving cell = the leaf driver of this block's own act_o[b] net.  qb5_act_drv: {b lib_cell pin ...} of every
# act_o[b] (one driver per bit, else an error); qb5_act_drv_apply <drv>: set_driving_cell of each act[b] (grouped by
# lib cell / pin; the library is the tool's for the current corner) + one QB5_ACT_DRV line (bits per lib cell).
proc qb5_act_drv {} {
    set dv {}
    foreach_in_collection p [get_ports {act_o[*]}] {
        regexp {\[(\d+)\]$} [get_object_name $p] -> b
        set d [get_pins -quiet -leaf -of_objects [get_nets -of_objects $p] -filter "direction==out"]
        if {[sizeof_collection $d] != 1} { error "qb5_act_drv: [sizeof_collection $d] drivers on [get_object_name $p]" }
        lappend dv $b [get_attribute [get_cells -of_objects $d] ref_name] [lindex [split [get_object_name $d] /] end]
    }
    return $dv
}
proc qb5_act_drv_apply {dv} {
    foreach {b c pin} $dv { lappend g([list $c $pin]) "act\[$b\]" }
    set h {}
    foreach k [lsort [array names g]] {
        lassign $k c pin
        set_driving_cell -lib_cell $c -pin $pin [get_ports $g($k)]
        lappend h "$c/$pin [llength $g($k)]"
    }
    puts "QB5_ACT_DRV [expr {[llength $dv] / 3}] act ports, driving cell = own act_o driver: [join $h {, }]"
}
