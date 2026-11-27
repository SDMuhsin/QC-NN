# The act chain contract (R107): act source (the act-supply block qb_act2_blk, blocks/act/io_budget.tcl) -> column 0 ->
# act_o -> column 1 -> ... -> column 7 (blocks/col/io_budget.tcl).  Both ends read their act budget from here and only
# from here: the values are sign-off limits of common/limits.txt (qb_limit; an environment override fails the verdict's
# limits gate), and each end's IO budget checks its own act lines against the contract (qb_act_chain_check), so the two
# ends cannot drift apart.  (Hunt round 11 on d1978e1: the hold budget was an env.sh export only the column read, the act
# budget had act -min 0.0 and gave itself 0.10 P launch where the column assumed 0.06 P.)
#   qb_act_hold    QC_ACT_HOLD_HUB (ns): the act hold budget, allocated once, to the act source (R81, PI decision): the
#                  source's act output -min = -H, every column's act input -min = its generic hold bound + H (act is a
#                  point-to-point chain of identical columns, each adding its feedthrough, so the earliest act arrival at
#                  any column is the source's guaranteed minimum).  Basis of 0.10 ns: R80 [M] act -> u_pe hold demand
#                  0.066-0.070 ns at ff / ml plus a derate spread up to 0.074 ns (R80 [M]: without it the column-0
#                  launch bound was applied to all 8 columns, 18042 hold buffers in u_pe)
#   qb_act_launch  QB_ACT_LAUNCH (fraction of P): the act source's launch (clock -> Q of its last act pipe flop + wire to
#                  column 0's act pins): the source's act output -max = (1 - launch) P - U (U = setup uncertainty, counted
#                  once, on the top-level flop -> flop path), the column's act input -max = launch P + its upstream
#                  feedthroughs (blocks/col/io_budget.tcl)
source [file join [file dirname [file normalize [info script]]] limits.tcl]
proc qb_act_hold {} { qb_limit QC_ACT_HOLD_HUB }
proc qb_act_launch {} { qb_limit QB_ACT_LAUNCH }
# qb_act_chain_check <end> <lines> <per> <smax> <smin>: error unless the SDC <lines> of one end's budget at period <per>
# have exactly one -max and one -min line on act[*] (end src: set_output_delay, end col: set_input_delay) and their
# values are the contract's (to the lines' 0.1 ps), given the end's own shifts <smax> / <smin> (ns: clock arrival terms, the column's
# upstream feedthroughs): src -max = (1 - launch) P - U + smax, -min = smin - H; col -max = launch P + smax, -min = smin + H.
# Returns "act chain <end>: -max <v> -min <v> = contract (launch <f> P, hold <H> ns)".
proc qb_act_chain_check {end lines per smax smin} {
    set U [qb_limit QC_UNC_SETUP]; set H [qb_act_hold]; set a [qb_act_launch]
    switch $end {
        src { set cmd set_output_delay; set want [list [expr {(1.0 - $a) * $per - $U + $smax}] [expr {$smin - $H}]] }
        col { set cmd set_input_delay;  set want [list [expr {$a * $per + $smax}] [expr {$smin + $H}]] }
        default { error "qb_act_chain_check: end '$end' is not src or col" }
    }
    set got {}
    foreach m {max min} w $want {
        set v [regexp -all -inline -line [format {^%s -%s (\S+) -clock qb_clk \[get_ports \{act\[\*\]\}\]$} $cmd $m] $lines]
        if {[llength $v] != 2} { error "qb_act_chain_check $end: [expr {[llength $v] / 2}] '$cmd -$m ... act\[*\]' lines (want 1)" }
        set v [lindex $v 1]
        if {![string is double -strict $v] || abs($v - $w) > 5.1e-5} {
            error "qb_act_chain_check $end: act\[*\] $cmd -$m $v != contract [format %.4f $w] (common/act_chain.tcl: launch $a P, hold $H ns)"
        }
        lappend got $v
    }
    return "act chain $end: -max [lindex $got 0] -min [lindex $got 1] = contract (launch $a P, hold $H ns)"
}
