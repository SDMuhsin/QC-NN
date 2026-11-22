# IO budget of the act-supply hard block qb_act2_blk (results/r7c.md), fractions of the period P, relative to the
# clock at the top-level flops; after CTS shifted by the block insertion delay L (inputs + L, outputs - L), as
# blocks/col/io_budget.tcl for the column block.  Used by blocks/act/act.cfg (P&R SDC), repair/post_cts.tcl (QB_IO_BUDGET),
# signoff/pt/act_blk.tcl and repair/block_io.tcl.  Knobs QB7_DIN / QB7_CIN / QB7_AOUT differ by step (blocks/act/act.env).
#   data in   s_q (S read, 2 048 b) / m_q (map read, 512 b): S / map macro clk->Q + top rotator / mux + wire; the block
#             only registers them (sdq / rdq): max QB7_DIN (default 0.70 P), min 0.05 P
#   ctl in    pass commands, tokens, load permissions, flag port (sequencer / glue): max QB7_CIN (default 0.40 P)
#   act out   4 608 b, from the last act pipe flop straight to column 0's act pins (abutted): the column's act input
#             budget (0.55 P) assumes launch + top wire 0.06 P; the block may use QB7_AOUT (default 0.10 P) for
#             clk->Q + pin wire; U (setup uncertainty) is counted on the column side, so the output delay is
#             (1 - QB7_AOUT) P - U
#   ctl out   busy / done / l_pos / map and S read port / descriptors / err: block may use 0.40 P (output 0.60 P)
proc qb7_env {n d} { expr {[info exists ::env($n)] && $::env($n) ne "" ? $::env($n) : $d} }
proc qb7_budget {} {
    return [list \
        in  {s_q[*] m_q[*]}                                    [qb7_env QB7_DIN 0.70] 0.05 0 \
        in  {start[*] c_* tgo[*] l_ok[*] l_seq* f_*}           [qb7_env QB7_CIN 0.40] 0.05 0 \
        out {act[*]}                                           [expr {1.0 - [qb7_env QB7_AOUT 0.10]}] 0.0 1 \
        out {busy[*] done[*] l_pos* m_ren m_ra[*] m_ctx s_ren s_ra[*] s_ctx d_* a_* err} 0.60 0.0 0]
}
# SDC lines at period per, shifted by the insertion delay L (0 for ideal clocks)
proc qb7_io_lines {per {L 0.0}} {
    set out {}
    set U [qb7_env QC_UNC_SETUP 0.25]
    foreach {d pats mx mn subu} [qb7_budget] {
        set s [expr {$d eq "in" ? $L : -$L}]
        set su [expr {$subu ? $U : 0.0}]
        set cmd [expr {$d eq "in" ? "set_input_delay" : "set_output_delay"}]
        lappend out [format "%s -max %.4f -clock qb_clk \[get_ports {%s}\]" $cmd [expr {$mx * $per + $s - $su}] $pats]
        lappend out [format "%s -min %.4f -clock qb_clk \[get_ports {%s}\]" $cmd [expr {$mn * $per + $s}] $pats]
    }
    return [join $out "\n"]
}
proc qb7_io_apply {per {L 0.0}} { foreach l [split [qb7_io_lines $per $L] "\n"] { uplevel #0 $l } }
# hook interface of repair/post_cts.tcl (QB_IO_BUDGET = this file): the post-CTS IO delays
proc qb5_io_apply {per {L 0.0}} { qb7_io_apply $per $L }
