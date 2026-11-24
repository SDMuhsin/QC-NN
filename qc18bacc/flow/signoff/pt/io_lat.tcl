# Clock arrival at the block's own register clock pins, PrimeTime's IO budget shift of a propagated clock (R77;
# signoff/pt/common.tcl qb_pt_lat, col_blk.tcl; ICC2 times the same late / early ends with compute_clock_latency,
# flow/icc2/common.tcl qb_io_lat).  The top-level tree
# is balanced with the block's sinks, so an external register's clock arrives at about the p50 sink arrival; the timer's
# late (late OCV derate) and early (early derate) rise arrivals give the two ends (blocks/col/io_budget.tcl header: which
# check takes which).  ICC2 has no pin arrival attributes (R77 [M]: list_attributes -class pin; clock_latency_rise_max /
# _min stay empty on the register clock pins after update_timing).
#   qb_clk_arrival late|early  "<p50> <n> <min> <max> <p10> <p90>" of max_rise_arrival / min_rise_arrival over
#                          all_registers -clock_pins of the current PrimeTime corner; error if no pin has a value
proc qb_clk_arrival {which} {
    set attr [dict get {late max_rise_arrival early min_rise_arrival} $which]
    set v {}
    foreach a [get_attribute -quiet [all_registers -clock_pins] $attr] { if {[string is double -strict $a]} { lappend v $a } }
    set v [lsort -real $v]; set n [llength $v]
    if {!$n} { error "qb_clk_arrival: no $attr on the register clock pins" }
    return [list [format %.3f [lindex $v [expr {$n / 2}]]] $n [lindex $v 0] [lindex $v end] [lindex $v [expr {$n / 10}]] [lindex $v [expr {9 * $n / 10}]]]
}
