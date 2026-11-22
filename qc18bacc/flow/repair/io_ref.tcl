# Per-corner clock latency of a block IO budget in a multi-corner OpenROAD session (R50, results/r50.md sec. 2).
# The IO budgets (blocks/act/io_budget.tcl, blocks/hub/sdc.py hub_io.tcl, ...) shift every delay by a constant insertion
# delay L (inputs +L, outputs -L: the launching / capturing top flop's clock arrives like the block's own flops).  SDC has
# no per-corner IO delay, so with tt and ss loaded the ss corner would see the tt L: r48_act, IO budget at tt L 0.842, ss
# inputs 0.4 ns early -> ss hold -0.344 / 2 576 endpoints in OR (PT ss: 0) and 9 490 hold buffers.
# qb_io_ref <L_tt> <script> runs the IO hook <script> with set_input_delay / set_output_delay re-anchored to a reference
# register clock pin (-reference_pin, the p50 pin by clock arrival): each delay loses its constant L and gains the
# reference pin's own arrival at every corner, offset so that tt equals L_tt (the PT tt p50):
#   input  d' = d - L_tt + (L_tt - A_tt) = d - A_tt          (arrival = A_c + d - A_tt; at tt = d)
#   output d' = d + L_tt - (L_tt - A_tt) = d + A_tt          (required = P + A_c - d - A_tt; at tt as before)
# A_c = OR clock arrival of the reference pin at corner c; tt is the fastest loaded corner (smallest arrival).
proc qb_io_ref_pin {} {
    set a {}
    foreach p [all_registers -clock_pins] {
        set v [get_property $p arrival_max_rise]
        if {[string is double -strict $v]} { lappend a [list $v $p] }
    }
    if {![llength $a]} { error "qb_io_ref: no clocked register pins" }
    set p [lindex [lsort -real -index 0 $a] [expr {[llength $a] / 2}] 1]
    sta::redirect_string_begin; report_arrival $p; set s [sta::redirect_string_end]
    # " (qb_clk ^) r <min>:<max>:<min>:<max> f ..." one min:max pair per corner
    if {![regexp {\^\) r (\S+)} $s -> r]} { error "qb_io_ref: no rise arrival for [get_full_name $p]: $s" }
    set v {}; foreach x [split $r :] { if {[string is double -strict $x]} { lappend v $x } }
    return [list $p [tcl::mathfunc::min {*}$v] [tcl::mathfunc::max {*}$v]]
}
proc qb_io_ref_wrap {cmd sign args} {
    set out {}; set done 0; set skip 0
    foreach a $args {
        if {$skip} { lappend out $a; set skip 0; continue }
        if {$a in {-clock -reference_pin}} { lappend out $a; set skip 1; continue }
        if {!$done && [string is double -strict $a]} { lappend out [expr {$a + $sign * $::qb_io_ref_A}]; set done 1; continue }
        lappend out $a
    }
    uplevel 1 [list qb_io_ref_orig_$cmd {*}$out -reference_pin $::qb_io_ref_P]
}
# qb_io_ref_eval <script>: run Tcl with the same re-anchoring (the reference pin chosen by qb_io_ref), e.g. a hook that
# edits IO delays after the budget (repair/hub_setup_pre.tcl output -min); a delay set without the reference pin would be a
# second port-delay entry with the constant L.
proc qb_io_ref_eval {script} {
    rename ::set_input_delay ::qb_io_ref_orig_set_input_delay
    rename ::set_output_delay ::qb_io_ref_orig_set_output_delay
    proc ::set_input_delay {args} { uplevel 1 [list qb_io_ref_wrap set_input_delay -1 {*}$args] }
    proc ::set_output_delay {args} { uplevel 1 [list qb_io_ref_wrap set_output_delay 1 {*}$args] }
    set rc [catch { uplevel #0 $script } e]
    rename ::set_input_delay {}; rename ::set_output_delay {}
    rename ::qb_io_ref_orig_set_input_delay ::set_input_delay
    rename ::qb_io_ref_orig_set_output_delay ::set_output_delay
    if {$rc} { error $e }
}
proc qb_io_ref {L script} {
    lassign [qb_io_ref_pin] ::qb_io_ref_P ::qb_io_ref_A amax
    qb_io_ref_eval [list source $script]
    puts [format "QB_IO_REF IO budget anchored to %s: OR arrival tt %.3f / slowest corner %.3f, tt L %s (offset %+.3f)" \
        [get_full_name $::qb_io_ref_P] $::qb_io_ref_A $amax $L [expr {$L - $::qb_io_ref_A}]]
}
