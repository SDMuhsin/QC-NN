# IO budget of the act-supply hard block qb_act2_blk (results/r7c.md), fractions of the period P, relative to the
# clock at the top-level flops; after CTS shifted by the block insertion delay L (inputs + L, outputs - L), as
# blocks/col/io_budget.tcl for the column block.  Used by the act DC (synth/act_dc_hook.tcl; the OpenROAD-era act P&R that
# read it too was removed, flow/README.md).  Knobs QB7_DIN / QB7_CIN (environment; declared below, so DC records them in
# run.env: flow/tsmc65/common/knobs.tcl).
#   data in   s_q (S read, 2 048 b) / m_q (map read, 512 b): S / map macro clk->Q + top rotator / mux + wire; the block
#             only registers them (sdq / rdq): max QB7_DIN (default 0.70 P), min 0.05 P
#   ctl in    pass commands, tokens, load permissions, flag port (sequencer / glue): max QB7_CIN (default 0.40 P)
#   act out   4 608 b, from the last act pipe flop straight to column 0's act pins (abutted): the source end of the act
#             chain (common/act_chain.tcl, R107; one contract with the column's act input): the block may use
#             QB_ACT_LAUNCH (0.06 P) for clk->Q + pin wire, which is what the column's act input budget assumes; U (setup
#             uncertainty) is counted on the column side, so the output delay is (1 - QB_ACT_LAUNCH) P - U.  min:
#             the chain's hold guarantee at a driving port, qb_act_out_min L = U_hold - (L + QC_ACT_HOLD_HUB): act changes
#             no earlier than H after the clock edge, this block's clock -> Q included (R81 budget; R108 one guarantee
#             with the column's act input and act_o, common/act_chain.tcl).  (Hunt round 11 on d1978e1: the launch
#             was a knob QB7_AOUT of default 0.10 P and the min 0.0, two values beside the column's.)
#   ctl out   busy / done / l_pos / map and S read port / descriptors / err: block may use 0.40 P (output 0.60 P)
# setup uncertainty U: common/limits.txt through qb_limit (R102; before, QC_UNC_SETUP was read from the environment with
# its own default 0.25, outside the committed limits)
source [file join [file dirname [file normalize [info script]]] .. .. common act_chain.tcl]
qc_knobs_declare {QB7_DIN 0.70 QB7_CIN 0.40}
proc qb7_budget {} {
    return [list \
        in  {s_q[*] m_q[*]}                                    [qc_knob QB7_DIN] 0.05 0 \
        in  {start[*] c_* tgo[*] l_ok[*] l_seq* f_*}           [qc_knob QB7_CIN] 0.05 0 \
        out {act[*]}                                           [expr {1.0 - [qb_act_launch]}] 0.0 1 \
        out {busy[*] done[*] l_pos* m_ren m_ra[*] m_ctx s_ren s_ra[*] s_ctx d_* a_* err} 0.60 0.0 0]
}
# SDC lines at period per, shifted by the insertion delay L (0 for ideal clocks); act -min = qb_act_out_min L; the act
# lines checked against the act chain contract (common/act_chain.tcl qb_act_chain_check)
proc qb7_io_lines {per {L 0.0}} {
    set out {}
    set U [qb_limit QC_UNC_SETUP]
    foreach {d pats mx mn subu} [qb7_budget] {
        set s [expr {$d eq "in" ? $L : -$L}]
        set su [expr {$subu ? $U : 0.0}]
        set cmd [expr {$d eq "in" ? "set_input_delay" : "set_output_delay"}]
        lappend out [format "%s -max %.4f -clock qb_clk \[get_ports {%s}\]" $cmd [expr {$mx * $per + $s - $su}] $pats]
        lappend out [format "%s -min %.4f -clock qb_clk \[get_ports {%s}\]" $cmd [expr {$pats eq {act[*]} ? [qb_act_out_min $L] : $mn * $per + $s}] $pats]
    }
    qb_act_chain_check src [join $out "\n"] $per [expr {-$L}] $L
    return [join $out "\n"]
}
proc qb7_io_apply {per {L 0.0}} { foreach l [split [qb7_io_lines $per $L] "\n"] { uplevel #0 $l } }
