# Clock arrival at the block's own register clock pins, PrimeTime's IO budget shift of a propagated clock (R77;
# signoff/pt/common.tcl qb_pt_lat, col_blk.tcl; ICC2 times the same late / early ends with compute_clock_latency,
# flow/icc2/common.tcl qb_io_lat).  The top-level tree
# is balanced with the block's sinks, so an external register's clock arrives at about the p50 sink arrival; the timer's
# late (late OCV derate) and early (early derate) rise arrivals give the two ends (blocks/col/io_budget.tcl header: which
# check takes which).  ICC2 has no pin arrival attributes (R77 [M]: list_attributes -class pin; clock_latency_rise_max /
# _min stay empty on the register clock pins after update_timing).
# One input-port latency definition in both tools (R85, PI decision 2): the median over the registers on IO paths, ICC2's
# compute_clock_latency definition ("Computed using: io pair regs", r84diag d7.txt [M] 9289 regs).  Before R85 PrimeTime
# took the p50 over all register clock pins, ICC2 over the IO-path registers: r84 [M] 7.3 ps apart at wcl (the whole ICC2 /
# PT wcl hold difference of r84 item 3).
#   qb_io_reg_clock_pins   clock pins of the IO-path registers: non-clock-gating registers captured from a non-clock
#                          input port (all_fanout endpoints) or launching to an output port (all_fanin startpoints)
#   qb_clk_arrival late|early  "<p50> <n> <min> <max> <p10> <p90>" of max_rise_arrival / min_rise_arrival over
#                          qb_io_reg_clock_pins of the current PrimeTime corner; error if no pin has a value
proc qb_io_reg_clock_pins {} {
    set in [remove_from_collection [all_inputs] [get_attribute [get_clocks] sources]]
    # (endpoints / startpoints are pins and ports: the ports are dropped)
    set ep [filter_collection [all_fanout -from $in -endpoints_only -flat] "object_class==pin"]
    set sp [filter_collection [all_fanin -to [all_outputs] -startpoints_only -flat] "object_class==pin"]
    set c [get_cells -quiet -of_objects [add_to_collection $ep $sp]]
    set c [filter_collection $c "is_sequential==true && is_integrated_clock_gating_cell!=true"]
    return [remove_from_collection -intersect [all_registers -clock_pins] [get_pins -of_objects $c]]
}
proc qb_clk_arrival {which} {
    set attr [dict get {late max_rise_arrival early min_rise_arrival} $which]
    if {![info exists ::QB_IO_REG_CP]} { set ::QB_IO_REG_CP [qb_io_reg_clock_pins] }
    set v {}
    foreach a [get_attribute -quiet $::QB_IO_REG_CP $attr] { if {[string is double -strict $a]} { lappend v $a } }
    set v [lsort -real $v]; set n [llength $v]
    if {!$n} { error "qb_clk_arrival: no $attr on the IO-path register clock pins" }
    return [list [format %.3f [lindex $v [expr {$n / 2}]]] $n [lindex $v 0] [lindex $v end] [lindex $v [expr {$n / 10}]] [lindex $v [expr {9 * $n / 10}]]]
}
