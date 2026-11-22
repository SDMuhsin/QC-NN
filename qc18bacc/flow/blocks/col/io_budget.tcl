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
