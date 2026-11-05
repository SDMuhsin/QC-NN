# Shared Tcl of flow/tsmc65 (DC and PrimeTime): kit config, environment, constraints, summary lines.
set ::QC_FLOW [file normalize [file dirname [info script]]/..]
source $::QC_FLOW/site/site.tcl
source $::QC_FLOW/common/flist.tcl

proc qc_env {name {default ""}} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $default
}
proc qc_db {corner} { return $::QC_LIBDIR/$::QC_LIB($corner).db }
# Extra link libraries per corner (e.g. compiled SRAM macros, linked as black boxes): the .db files listed in the
# environment variable QC_EXTRA_DB_SS / _TT / _FF (whitespace separated, same order in every corner).
proc qc_extra_dbs {corner} { return [qc_env QC_EXTRA_DB_[string toupper $corner]] }

# Generic single-clock constraints (used unless QC_SDC names a design SDC).
#   clock on port <clk> (virtual clock if the port does not exist), period <period> ns;
#   setup / hold uncertainty QC_UNC_SETUP / QC_UNC_HOLD (0.25 / 0.05 ns), clock transition 0.15 ns;
#   input / output delay <io_pct> % of the period on all non-clock ports; site driver cells, 4 x site load pin;
#   max transition min(0.5, 0.1 P), max fanout 16.
proc qc_constraints {clk period corner io_pct} {
    set lib $::QC_LIB($corner)
    set iod [expr {$period * $io_pct / 100.0}]
    if {[sizeof_collection [get_ports -quiet $clk]]} {
        create_clock -name $clk -period $period [get_ports $clk]
        set_driving_cell -lib_cell [lindex $::QC_DRV_CLK 0] -library $lib -pin [lindex $::QC_DRV_CLK 1] [get_ports $clk]
        set data_in [remove_from_collection [all_inputs] [get_ports $clk]]
    } else {
        create_clock -name $clk -period $period
        set data_in [all_inputs]
    }
    set_clock_uncertainty -setup [qc_env QC_UNC_SETUP 0.25] [get_clocks $clk]
    set_clock_uncertainty -hold  [qc_env QC_UNC_HOLD 0.05]  [get_clocks $clk]
    set_clock_transition 0.15 [get_clocks $clk]
    set_input_delay  $iod -clock $clk $data_in
    set_output_delay $iod -clock $clk [all_outputs]
    set_driving_cell -lib_cell [lindex $::QC_DRV_IN 0] -library $lib -pin [lindex $::QC_DRV_IN 1] $data_in
    set_load [expr {4.0 * [load_of $lib/$::QC_LOAD_PIN]}] [all_outputs]
    set_max_transition [expr {min(0.5, 0.1 * $period)}] [current_design]
    set_max_fanout 16 [current_design]
}
proc qc_apply_constraints {corner} {
    set sdc [qc_env QC_SDC]
    if {$sdc ne ""} { source $sdc; return }
    qc_constraints [qc_env QC_CLK clk] [qc_env QC_PERIOD] $corner [qc_env QC_IO_PCT 20]
}

# Worst setup / hold path summary lines (works in DC and PT).
proc qc_put_timing {fh} {
    foreach {kind dt} {setup max hold min} {
        set p [get_timing_paths -delay_type $dt -max_paths 1]
        set s NA; set sp NA; set ep NA
        if {[sizeof_collection $p]} {
            set s [get_attribute $p slack]
            set sp [get_object_name [get_attribute $p startpoint]]
            set ep [get_object_name [get_attribute $p endpoint]]
        }
        set tns 0.0; set nvio 0
        foreach_in_collection q [get_timing_paths -delay_type $dt -max_paths 100000 -slack_lesser_than 0] {
            set tns [expr {$tns + [get_attribute $q slack]}]; incr nvio
        }
        puts $fh [format "%s_wns_ns %s %s_tns_ns %.3f %s_viol_endpoints %d" $kind $s $kind $tns $kind $nvio]
        puts $fh "${kind}_worst_path $sp -> $ep"
    }
}
