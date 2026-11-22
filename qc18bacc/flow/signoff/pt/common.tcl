# PrimeTime helpers shared by the block sign-off / ETM scripts (signoff/pt/col_blk.tcl, act_blk.tcl, hub.tcl,
# signoff/etm/etm.tcl).
#   qb_pt_lat <dir> <corner>  insertion delay L of this corner: p50 of the rise arrival at every register / macro clock pin
#                             (the definition the P&R uses, cts/clk_lat.tcl); "<p50> <min> <max>" written to
#                             <dir>/out/clk_lat_<corner>.txt, which the chip top reads (blocks/top/run.sh views)
#   qb_pt_drv <fh>            sign-off DRV line: max-transition and max-capacitance violators (design + library limits)
#   qb_etm_inputs             ETM extraction context (R45 bug 2): no driving cell on the data inputs (constraints.sdc /
#                             the hub SDC put a BUFFD4 there, extract_model then varied the BUFFD4 *input* slew: MEXT-81
#                             and the column tt outlier tables), ideal input ramp: the ETM index is the port slew
proc qb_pt_lat {dir corner} {
    set v {}
    foreach a [get_attribute -quiet [all_registers -clock_pins] max_rise_arrival] { if {[string is double -strict $a]} { lappend v $a } }
    set v [lsort -real $v]; set n [llength $v]
    if {!$n} { puts "QB_PT_LAT no clock-pin arrivals"; return 0.0 }
    set L [format %.3f [lindex $v [expr {$n / 2}]]]
    file mkdir $dir/out; set f [open $dir/out/clk_lat_$corner.txt w]; puts $f "$L [lindex $v 0] [lindex $v end]"; close $f
    puts [format "QB_PT_LAT %s L %s (p50 of %d clock pins; p10 %.3f p90 %.3f max %.3f)" $corner $L $n \
        [lindex $v [expr {$n / 10}]] [lindex $v [expr {9 * $n / 10}]] [lindex $v end]]
    return $L
}
proc qb_pt_drv {fh} {
    redirect -variable t { report_constraint -max_transition -all_violators -nosplit }
    redirect -variable c { report_constraint -max_capacitance -all_violators -nosplit }
    puts $fh "drv max_transition_violators [regexp -all -line {VIOLATED} $t] max_capacitance_violators [regexp -all -line {VIOLATED} $c] (design max_transition [get_attribute [current_design] max_transition])"
}
proc qb_etm_inputs {} {
    set din [remove_from_collection [all_inputs] [get_ports {clk}]]
    remove_driving_cell $din
    set_input_transition 0 $din
    puts "QB_ETM inputs: driving cells removed, input transition 0 on [sizeof_collection $din] ports"
}
