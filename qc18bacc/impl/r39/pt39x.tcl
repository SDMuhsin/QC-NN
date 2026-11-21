# QB_PT_EXTRA of impl/r5b/pt_chip.tcl for the R39 chip sign-off (results/r39.md): the R37 block conditions at chip level
# and a full violator list.  Appends to pt_chip_<corner>.txt; violators -> rpt/r39_<corner>_viol.txt.
#   hub_ft     paths through a hub ETM input pin AND a hub ETM output pin (R37: 47 tt / 97 ss in2out feed-through
#              endpoints were set false in the block PT and must be timed here end to end)
#   hub2act    paths from the hub into the act (s_q / m_q, R37 split hub 0.26 P / act 0.74 P)
#   act2col    paths from the act into the column blocks (R37 act output budget 0.25 P)
#   check_timing: unconstrained endpoints (a cross-block arc missing in an ETM shows up as unconstrained, not violated)
set hub [get_cells -hierarchical -filter "ref_name==qb_hub"]
set act [get_cells -hierarchical -filter "ref_name==qb_act2_blk"]
set hi [get_pins -of_objects $hub -filter "direction==in"]; set ho [get_pins -of_objects $hub -filter "direction==out"]
set ai [get_pins -of_objects $act -filter "direction==in"]; set ao [get_pins -of_objects $act -filter "direction==out"]
foreach dt {max min} {
    set k [expr {$dt eq "max" ? "" : "hold_"}]
    set ft [get_timing_paths -delay_type $dt -through $hi -through $ho -max_paths 100000 -nworst 1]
    set nv 0; set ws 1e9
    foreach_in_collection p $ft { set s [get_attribute $p slack]; if {$s < $ws} { set ws $s }; if {$s < 0} { incr nv } }
    puts $fh [format "${k}hub_ft endpoints %d violators %d worst_slack %s" [sizeof_collection $ft] $nv [expr {$ws < 1e8 ? [format %.3f $ws] : "NA"}]]
    fl $fh ${k}hub2act [get_timing_paths -delay_type $dt -max_paths 1 -from $hub -to $ai] $per
    fl $fh ${k}act2col [get_timing_paths -delay_type $dt -max_paths 1 -from $act -to $bi] $per
    fl $fh ${k}io_in   [get_timing_paths -delay_type $dt -max_paths 1 -from [remove_from_collection [all_inputs] [get_ports clk]]] $per
    fl $fh ${k}io_out  [get_timing_paths -delay_type $dt -max_paths 1 -to [all_outputs]] $per
}
redirect -variable ct { check_timing -verbose }
puts $fh "check_timing_unconstrained_endpoints [regexp -all -line {unconstrained} $ct] (see rpt/r39_${corner}_check_timing.rpt)"
set f [open $dir/rpt/r39_${corner}_check_timing.rpt w]; puts $f $ct; close $f
set f [open $dir/rpt/r39_${corner}_viol.txt w]
foreach dt {max min} {
    foreach_in_collection p [get_timing_paths -delay_type $dt -max_paths 100000 -nworst 1 -slack_lesser_than 0] {
        puts $f [format "%s %.3f %s -> %s" [expr {$dt eq "max" ? "setup" : "hold"}] [get_attribute $p slack] \
            [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
    }
}
close $f
# R39LAT: clock arrival at the TOP registers' clock pins (blocks / macros excluded) of this corner: the IO shift L
# (QB36_TOPL) should be this corner's p50 (R37 lesson: ss PT with the tt L mis-models every IO path).
set rc [remove_from_collection [all_registers -clock_pins] [get_pins -of_objects [add_to_collection [add_to_collection [add_to_collection $blk $hub] $act] $mac]]]
set v {}
foreach_in_collection p $rc { set a [get_attribute -quiet $p max_rise_arrival]; if {[string is double -strict $a]} { lappend v $a } }
set v [lsort -real $v]; set n [llength $v]
if {$n} { puts $fh [format "R39LAT %s top_reg_clk_pins %d p10 %.3f p50 %.3f p90 %.3f min %.3f max %.3f (io shift L used %s)" $corner $n \
    [lindex $v [expr {int(0.1 * ($n - 1))}]] [lindex $v [expr {int(0.5 * ($n - 1))}]] [lindex $v [expr {int(0.9 * ($n - 1))}]] [lindex $v 0] [lindex $v end] [qc_env QB35_TOPL 0]] }
foreach c [list $hub $act] { foreach_in_collection q [get_pins -of_objects $c -filter "lib_pin_name==clk"] { puts $fh [format "R39BLKCLK %s %s" [get_object_name $q] [get_attribute -quiet $q max_rise_arrival]] } }
