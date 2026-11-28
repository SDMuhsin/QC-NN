# The act chain contract (R107): act source (the act-supply block qb_act2_blk, blocks/act/io_budget.tcl) -> column 0 ->
# act_o -> column 1 -> ... -> column 7 (blocks/col/io_budget.tcl).  Both ends read their act budget from here and only
# from here: the values are sign-off limits of common/limits.txt (qb_limit; an environment override fails the verdict's
# limits gate), and each end's IO budget checks its own act lines against the contract (qb_act_chain_check), so the two
# ends cannot drift apart.  (Hunt round 11 on d1978e1: the hold budget was an env.sh export only the column read, the act
# budget had act -min 0.0 and gave itself 0.10 P launch where the column assumed 0.06 P.)
#   qb_act_hold    QC_ACT_HOLD_HUB (ns): the act hold budget H, allocated once, to the act source (R81, PI decision).
#                  Basis of 0.10 ns: R80 [M] act -> u_pe hold demand 0.066-0.070 ns at ff / ml plus a derate spread up to
#                  0.074 ns (R80 [M]: without it the column-0 launch bound was applied to all 8 columns, 18042 hold
#                  buffers in u_pe)
#   qb_act_earliest <E>   THE hold guarantee of the chain (R108): act changes no earlier than E + H, E = the clock edge
#                  at the block's own flops in its frame (source: its insertion delay L; column: its early register clock
#                  arrival Le), the launching flop's clock -> Q INCLUDED in H.  Every column's act input -min is this (act
#                  is a point-to-point chain of identical columns, each adding its feedthrough, so the earliest act arrival
#                  at any column is the source's guaranteed minimum).  (R108 [S]: the column assumed Le + Tq x early
#                  derate + H, but the source's output -min bounds its whole launch, clock -> Q included, by H: Tq was
#                  counted twice, a column hold margin no driver gave.)
#   qb_act_out_min <E>    the output -min of every act driver, the same guarantee stated at the driving port:
#                  U_hold - (E + H) (U_hold = QC_UNC_HOLD: the timer adds it to the port's own hold check, and the contract
#                  charges it once, at the capturing column's act flop; R79, PI decision).  The act source's act output
#                  (blocks/act/io_budget.tcl) and every column's act_o, the driver of the next column (blocks/col/
#                  io_budget.tcl qb5_act_o_min), so each delivers exactly E + H.  (R108: the source had -(L + H) and
#                  delivered H + U_hold while every act_o delivered H.)
#   qb_act_launch  QB_ACT_LAUNCH (fraction of P): the act source's launch (clock -> Q of its last act pipe flop + wire to
#                  column 0's act pins): the source's act output -max = (1 - launch) P - U (U = setup uncertainty, counted
#                  once, on the top-level flop -> flop path), the column's act input -max = launch P + its upstream
#                  feedthroughs (blocks/col/io_budget.tcl)
source [file join [file dirname [file normalize [info script]]] limits.tcl]
proc qb_act_hold {} { qb_limit QC_ACT_HOLD_HUB }
proc qb_act_launch {} { qb_limit QB_ACT_LAUNCH }
proc qb_act_earliest {E} { expr {$E + [qb_act_hold]} }
proc qb_act_out_min {E} { expr {[qb_limit QC_UNC_HOLD] - [qb_act_earliest $E]} }
#   qb_act_in_max <per> <smax>   a column's act input -max at period <per>: launch P + <smax> (the column's -max shift:
#                  its clock arrival term + the upstream feedthroughs, blocks/col/io_budget.tcl qb5_act_smax); the contract
#                  below and the column's feedthrough delay report (signoff/pt/col_blk.tcl, R118: was 0.55 P written there)
proc qb_act_in_max {per smax} { expr {[qb_act_launch] * $per + $smax} }
# qb_act_chain_check <end> <lines> <per> <smax> <E>: error unless the SDC <lines> of one end's budget at period <per>
# have exactly one -max and one -min line on act[*] (end src: set_output_delay, end col: set_input_delay) and their
# values are the contract's (to the lines' 0.1 ps), given the end's own -max shift <smax> (ns: clock arrival terms, the
# column's upstream feedthroughs) and its clock edge <E> (qb_act_earliest): src -max = (1 - launch) P - U + smax, -min =
# U_hold - (E + H); col -max = launch P + smax, -min = E + H.
# Returns "act chain <end>: -max <v> -min <v> = contract (launch <f> P, hold <H> ns, U_hold <u> ns)".
proc qb_act_chain_check {end lines per smax E} {
    set U [qb_limit QC_UNC_SETUP]; set Uh [qb_limit QC_UNC_HOLD]; set H [qb_act_hold]; set a [qb_act_launch]
    switch $end {
        src { set cmd set_output_delay; set want [list [expr {(1.0 - $a) * $per - $U + $smax}] [expr {$Uh - ($E + $H)}]] }
        col { set cmd set_input_delay;  set want [list [qb_act_in_max $per $smax] [expr {$E + $H}]] }
        default { error "qb_act_chain_check: end '$end' is not src or col" }
    }
    set got {}
    foreach m {max min} w $want {
        set v [regexp -all -inline -line [format {^%s -%s (\S+) -clock qb_clk \[get_ports \{act\[\*\]\}\]$} $cmd $m] $lines]
        if {[llength $v] != 2} { error "qb_act_chain_check $end: [expr {[llength $v] / 2}] '$cmd -$m ... act\[*\]' lines (want 1)" }
        set v [lindex $v 1]
        if {![string is double -strict $v] || abs($v - $w) > 5.1e-5} {
            error "qb_act_chain_check $end: act\[*\] $cmd -$m $v != contract [format %.4f $w] (common/act_chain.tcl: launch $a P, hold $H ns, U_hold $Uh ns)"
        }
        lappend got $v
    }
    return "act chain $end: -max [lindex $got 0] -min [lindex $got 1] = contract (launch $a P, hold $H ns, U_hold $Uh ns)"
}
