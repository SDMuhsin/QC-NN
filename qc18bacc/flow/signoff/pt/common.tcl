# PrimeTime helpers shared by the sign-off / ETM scripts (signoff/pt/col_blk.tcl, act_blk.tcl, hub.tcl, top_chip.tcl,
# signoff/etm/etm.tcl).  Sourcing it also sets the sign-off timer options (the callers read the SPEF and update_timing
# after it):
#   timing_crpr_threshold_ps 1 (PT default 5): exact clock reconvergence pessimism removal.  The CCS receiver model gives
#   the clock leaf nets different early / late loads (r55 ff: 0.214 / 0.348 pF behind cts_inv_32429549), so a flop pair on
#   one leaf net has ~5 ps of common-path pessimism; at the default threshold PT credited 0.4 ps of it (last common pin
#   placed 3 levels up), ICC2 (exact CRPR) 5.7 ps: the R54 / R55 ff hold misses on direct flop-to-flop paths (R55 [M]).
#   1 ps is PT's floor (R59 [M]: set to 0 / 0.1 it reads back 1), so a leaf-net split below ~1 ps still gets ~0 credit
#   (R59: t1_reg_10_ -> t2_reg_10_ PT 0.06 ps vs ICC2 1.6 ps); the analysis is already on_chip_variation (report_design).
#   si_enable_analysis true (R62): crosstalk delta delay / noise-aware timing on the coupled ICC2 SPEF (flow/icc2 qb_timer
#   time.si_enable_analysis).  The app variable alone does not keep the coupling: read_parasitics grounds every coupling
#   capacitance unless it is given -keep_capacitive_coupling (R63 [M]: "Reduced coupling capacitances : 2029860",
#   XTALK-011 "SI enabled but no SI data"), so every PrimeTime script reads its SPEF through qb_pt_spef.  common/env.sh
#   qb_pt gates it: a PT run fails on XTALK-011 or a non-zero reduced-coupling count.
#   qb_pt_spef <spef>         read_parasitics of the ICC2 SPEF with its coupling capacitances kept (SI); the side
#                             process's log goes to $QB_PT_PARA_LOG (common/env.sh qb_pt: <log>_parasitics.log, one per
#                             run, so two PT runs in one dir never share parasitics_command.log; R74 lost a log that way)
#   qb_pt_spef_file <dir> <top> <corner>  the block SPEF of a corner: <dir>/out/<top>_<corner>_pt.spef.gz (ICC2
#                             flow/icc2/extract.tcl, R71) or _pt.spef (OpenROAD def2spef flows); error if none or both
#   qb_pt_lat <dir> <corner>  insertion delay L of this corner: p50 of the late rise arrival at every register / macro clock
#                             pin (signoff/pt/io_lat.tcl qb_clk_arrival late); "<p50> <min> <max>" written to
#                             <dir>/out/clk_lat_<corner>.txt, which the chip top reads (blocks/top/run.sh views)
#   qb_pt_ann                 SPEF annotation line "total N rc_network N coupled_network N not_annotated N" (totals row
#                             of report_annotated_parasitics; with coupling kept it has the Coupled network column, R64)
#                             + the not-annotated split (driverless / loadless / pin_to_pin rows).  Annotation gate (R71):
#                             QB_PT_SIGNOFF unannotated_pin_to_pin N = the Not Annotated count of the "Pin to pin nets"
#                             rows (internal + boundary: nets with a driver and at least one load), -1 if the rows are
#                             missing; common/env.sh qb_pt fails on non-zero.  R68 [M] r68 ss: the 6090 not annotated =
#                             5913 driverless (DC's undriven hierarchical nets) + 177 loadless (SYNOPSYS_UNCONNECTED_*
#                             outputs), 0 pin-to-pin
#   qb_pt_paths <rpt> <a> ..  path report <rpt>: one report_timing per argument list <a>, each with -slack_lesser_than
#                             QB_PT_ANY_SLACK (R71: PrimeTime lists only violators when -max_paths / -nworst > 1 and no
#                             slack bound is given, so the R68 reports of clean runs were empty; with the bound the
#                             worst N paths are always on disk as sign-off evidence)
#   qb_pt_drv <fh>            sign-off DRV line: max-transition and max-capacitance violators (design + library limits);
#                             returns "max_transition N max_capacitance N" (a QB_PT_SIGNOFF gate line, col_blk.tcl)
#   qb_pt_si_checks <fh> <rpt> sign-off checks beyond delta delay (R67): crosstalk noise / glitch (update_noise on the
#                             coupled SPEF against the CCS-noise immunity of the libraries; report_noise -all_violators,
#                             every listed pin counts, above_low and below_high) and the clock pulse checks
#                             (report_constraint -min_pulse_width / -min_period -all_violators) -> <rpt>_noise.rpt,
#                             <rpt>_pulse.rpt, a "signoff ..." line to fh and QB_PT_SIGNOFF on stdout, which common/env.sh
#                             qb_pt gates (a non-zero count fails the PT run)
#   qb_etm_context            ETM extraction context (R45 bug 2): no driving cell on any input, clk included
#                             (constraints.sdc / the hub SDC put a BUFFD4 on the data inputs and a CKBD8 on clk,
#                             extract_model then varied the driving cell's *input* slew: MEXT-81, and the R63 clock
#                             tables ignored the clk slew), so the ETM index is the port slew.  extract_model writes an
#                             input pin's max_transition = the context slew of its port (R64 [M] on r62: input transition
#                             0 -> 0 on every input, 0.2 -> 0.2; a port set_max_transition or the extract_model_*_
#                             transition_limit variables leave it at 0), so every input gets the design max_transition
#                             (min(0.5, 0.1 P), constraints.sdc) as its input transition, and the tables are
#                             characterised up to that limit (extract_model_{data,clock}_transition_limit, default 5 ns).
#                             Output load index (R71): extract_model_capacitance_limit = the largest library
#                             max_capacitance of the cells driving the output ports (unset it is 64 pF, MEXT-6; R71 [M]
#                             r68 ss: 17 driver lib pins, 0.033 .. 0.790 pF).  The ETM tables start at 0 ns slew (R71 [M]
#                             index_1 0, 0.0311 .. 0.5), below the library's 0.0046 ns: the RC-011 extrapolation
#                             warnings of an ETM log are those zero-slew index points on the first cells behind the
#                             ports (r68 ss: slews 0.0001 .. 0.0004 ns)
#   OCV derate late 1.05 / early 0.95 on cell + net delays (common/derate.tcl, the same as the ICC2 timer), applied when
#   sourced (after the caller's constraints)
set_app_var timing_crpr_threshold_ps 1
set_app_var si_enable_analysis true
source [file normalize [file dirname [info script]]/../../common/derate.tcl]
qb_derate
source [file normalize [file dirname [info script]]/io_lat.tcl]
proc qb_pt_lat {dir corner} {
    lassign [qb_clk_arrival late] L n mn mx p10 p90
    file mkdir $dir/out; set f [open $dir/out/clk_lat_$corner.txt w]; puts $f "$L $mn $mx"; close $f
    puts [format "QB_PT_LAT %s L %s (p50 of %d clock pins; p10 %.3f p90 %.3f max %.3f)" $corner $L $n $p10 $p90 $mx]
    return $L
}
proc qb_pt_ann {} {
    redirect -variable ann { report_annotated_parasitics }
    foreach k {pin_to_pin driverless loadless} r {{Pin to pin} Driverless Loadless} {
        set n($k) 0; set m 0
        foreach {- v} [regexp -all -line -inline "^\\s*- $r nets\\s*\\|(?:\\s*\\d+\\s*\\|){5}\\s*(\\d+)\\s*\\|" $ann] { incr n($k) $v; incr m }
        if {$m != 2} { set n($k) -1 }
    }
    puts "QB_PT_SIGNOFF unannotated_pin_to_pin $n(pin_to_pin)"
    if {![regexp {\n\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|} $ann -> tot rc cc na]} { return NA }
    return "total $tot rc_network $rc coupled_network $cc not_annotated $na (driverless $n(driverless) loadless $n(loadless) pin_to_pin $n(pin_to_pin))"
}
set ::QB_PT_ANY_SLACK 1e9
proc qb_pt_paths {rpt args} {
    redirect $rpt { foreach a $args { report_timing -slack_lesser_than $::QB_PT_ANY_SLACK -nosplit {*}$a } }
}
proc qb_pt_drv {fh} {
    redirect -variable t { report_constraint -max_transition -all_violators -nosplit }
    redirect -variable c { report_constraint -max_capacitance -all_violators -nosplit }
    puts $fh "drv max_transition_violators [regexp -all -line {VIOLATED} $t] max_capacitance_violators [regexp -all -line {VIOLATED} $c] (design max_transition [get_attribute [current_design] max_transition])"
    return "max_transition [regexp -all -line {VIOLATED} $t] max_capacitance [regexp -all -line {VIOLATED} $c]"
}
proc qb_pt_spef {spef} {
    if {[info exists ::env(QB_PT_PARA_LOG)]} { set_app_var parasitics_log_file $::env(QB_PT_PARA_LOG) }
    read_parasitics -keep_capacitive_coupling -format spef $spef
}
proc qb_pt_spef_file {dir top corner} {
    set f [glob -nocomplain $dir/out/${top}_${corner}_pt.spef $dir/out/${top}_${corner}_pt.spef.gz]
    if {[llength $f] != 1} { error "qb_pt_spef_file: [llength $f] SPEFs of $top $corner in $dir/out ($f)" }
    return [lindex $f 0]
}
proc qb_etm_context {} {
    set in [all_inputs]
    set mt [get_attribute [current_design] max_transition]
    remove_driving_cell $in
    set_input_transition $mt $in
    set_app_var extract_model_data_transition_limit $mt
    set_app_var extract_model_clock_transition_limit $mt
    puts "QB_ETM inputs: driving cells removed, input transition = table limit = max_transition $mt on [sizeof_collection $in] ports"
    set drv [get_pins -quiet -leaf -of_objects [get_nets -of_objects [all_outputs]] -filter "direction==out"]
    set mc {}
    foreach_in_collection lp [get_lib_pins -quiet -of_objects $drv] {
        set v [get_attribute -quiet $lp max_capacitance]; if {[string is double -strict $v]} { lappend mc $v }
    }
    if {![llength $mc]} { error "qb_etm_context: no library max_capacitance on the [sizeof_collection $drv] output drivers" }
    set_app_var extract_model_capacitance_limit [tcl::mathfunc::max {*}$mc]
    puts "QB_ETM outputs: capacitance limit = max library max_capacitance of [llength $mc] driver lib pins ([sizeof_collection $drv] pins) = [tcl::mathfunc::max {*}$mc] pF"
}
proc qb_pt_si_checks {fh rpt} {
    update_noise
    redirect -variable n { report_noise -all_violators -nosplit }
    redirect ${rpt}_noise.rpt { puts $n }
    set nv [regexp -all -line {^\s*\S+ \(\S+\)\s+[-0-9.]+\s+[-0-9.]+\s+[-0-9.]+\s*$} $n]
    redirect -variable w { report_constraint -min_pulse_width -all_violators -nosplit }
    redirect -variable p { report_constraint -min_period -all_violators -nosplit }
    redirect ${rpt}_pulse.rpt { puts $w; puts $p }
    set l "noise $nv min_pulse_width [regexp -all -line {VIOLATED} $w] min_period [regexp -all -line {VIOLATED} $p]"
    puts $fh "signoff $l"
    puts "QB_PT_SIGNOFF $l"
}
