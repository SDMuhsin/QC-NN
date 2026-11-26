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
#   qb_pt_lat <dir> <corner>  insertion delay L of this corner: p50 of the late rise arrival at the IO-path register clock
#                             pins (signoff/pt/io_lat.tcl qb_clk_arrival late; ICC2's io pair regs, R85); "<p50> <min> <max>" written to
#                             <dir>/out/clk_lat_<corner>.txt, which the chip top reads (blocks/top/run.sh views), by a
#                             sign-off session only: a setup-only session (::QB_PT_SETUP_ONLY: the DMSA ECO scenarios,
#                             diagnostics) leaves the file alone.  The QB_PT_LAT log line carries the three values as written
#                             and says whether they were; signoff/verdict.py gate clk_lat: the file = the post step's line
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
#   qb_pt_clk_tran            the ONE clock-network transition limit (R92, PI decision; common/env.sh QC_CLK_TRAN_MAX,
#                             0.25 ns): set_max_transition -clock_path on every clock, applied when sourced, so the
#                             sign-off scripts and the DMSA ECO setup (drv_eco.tcl sources the block script) check and
#                             fix the clock network against it (before: the 0.5 ns design limit only; CTS builds to 0.15)
#   qb_pt_drv <fh>            sign-off DRV line: max-transition violators split into data pins and clock-network pins
#                             (get_clock_network_objects + the clock sources; the latter against QC_CLK_TRAN_MAX, with
#                             the worst clock-network transition) and max-capacitance violators; returns "max_transition
#                             N max_capacitance N clock_max_transition N" (a QB_PT_SIGNOFF gate line, col_blk.tcl)
#   qb_pt_async <fh>          recovery / removal violators (checks of asynchronous set / clear pins; report_constraint
#                             -recovery / -removal -all_violators): constraint types of their own, outside the -max_delay /
#                             -min_delay reports the setup / hold counts read.  The clock-gating checks are inside those
#                             ([M] r91b ss / ff, every check made to fail: the 227 clock_gating_setup / _hold endpoints
#                             of the ICG E pins, group **clock_gating_default**, are 227 of the 31527 -max_delay / -min_delay
#                             violators).  r91b has no async set / clear pin (all_registers -async_pins 0), so these counts
#                             guard a future one.  "async ..." line to fh; returns "recovery N removal N" (QB_PT_SIGNOFF)
#   qb_pt_check_count <check> violations of one check_timing check: 0 on "check_timing succeeded", else the sum of its
#                             "There are N" counts, -1 if it reports neither (a gate never passes on an unread report)
#   qb_pt_coverage <fh>       coverage gates (R92): what the checks above do NOT time must be explained by the design.
#                             "coverage ..." lines to fh and QB_PT_SIGNOFF counts (common/env.sh qb_pt fails on non-zero):
#                             unconstrained_endpoints (check_timing), unclocked_register_pins (register clock pins no
#                             clock reaches), loops (check_timing + loop-breaking disabled arcs), unexpected_disabled_arcs
#                             (every disabled arc of report_disable_timing must be flag p / C on a cell with an input
#                             pin on a tie-cell net, and every constant pin a tie output or such an input: r91b [M] 146
#                             TIEL + 1 TIEH -> 227 clock-gate TE pins + 1 EDFQD2 E = the 228 "invalid end points" of
#                             UITE-416; 910 arcs = 4 per gate + 2), floating_nets (a load and no driver; with
#                             qb_pt_ann's pin-to-pin gate every net with a load is driven and annotated: r91b [M] the
#                             829 driverless nets have no load, bus bits the flattened netlist leaves dangling)
#   qb_pt_si_checks <fh> <rpt> [<noise state>]  sign-off checks beyond delta delay (R67): the clock pulse checks
#                             (report_constraint -min_pulse_width / -min_period -all_violators), then crosstalk noise /
#                             glitch (update_noise on the coupled SPEF against the CCS-noise immunity of the libraries;
#                             report_noise -all_violators, every listed pin counts, above_low and below_high) ->
#                             <rpt>_pulse.rpt, <rpt>_noise.rpt, a "signoff ..." line to fh and QB_PT_SIGNOFF on stdout,
#                             which common/env.sh qb_pt gates (a non-zero count fails the PT run).
#                             <noise state> (R92): the block's command that puts the session into its noise-only
#                             analysis state (the column: blocks/col/io_budget.tcl qb5_act_noise_driver), run after
#                             the pulse checks and before update_noise; its record is the "noise_state ..." line, and
#                             noise_undriven_ports (check_timing no_driving_cell in that state: port-driven nets
#                             PrimeTime would hold with no driver model) joins the QB_PT_SIGNOFF counts.  The caller
#                             must have written every timing result before: the session is in the noise state afterwards
#   qb_pt_noise_pins <pins>   after update_noise: {violators text} of the given load pins from their si_noise_* pin
#                             attributes (above_low and below_high: pins PrimeTime analysed in detail, worst total bump,
#                             negative slacks; a net under its noise filter has no values and is not counted)
#   qb_pt_const_hold <corner> holding model of the constant drivers (R92): the kit's tie cells have no noise model
#                             (check_noise "none": r91b 147 driver pins, holding 227 clock-gate TE pins and one flop E),
#                             so a "noise 0" said nothing about those pins.  The kit does give the tie's resistance to
#                             its rail (liberty intrinsic_parasitic / intrinsic_resistance, signoff/pt/lib_hold_res.py
#                             on the corner's library: tc TIEL 1.285, TIEH 2.423 kohm); it becomes the lib pin's
#                             steady-state resistance (set_steady_state_resistance, above and below its rail) for every
#                             such cell the design uses.  Returns {record load_pins}; qb_pt_si_checks writes the
#                             "noise_hold ..." line and gates noise_undriven_pins = check_noise's "none" count after it
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
set ::QB_PT_DIR [file normalize [file dirname [info script]]]
set_app_var timing_crpr_threshold_ps 1
set_app_var si_enable_analysis true
source [file normalize [file dirname [info script]]/../../common/derate.tcl]
qb_derate
source [file normalize [file dirname [info script]]/io_lat.tcl]
proc qb_pt_lat {dir corner} {
    lassign [qb_clk_arrival late] L n mn mx p10 p90
    # a setup-only session (ECO scenario, diagnostic) must not replace the value a sign-off session recorded for the chip top
    set w [expr {![info exists ::QB_PT_SETUP_ONLY]}]
    if {$w} { file mkdir $dir/out; set f [open $dir/out/clk_lat_$corner.txt w]; puts $f "$L $mn $mx"; close $f }
    puts [format "QB_PT_LAT %s L %s min %s max %s (p50 / min / max of %d IO-path register clock pins; p10 %.3f p90 %.3f) %s" \
        $corner $L $mn $mx $n $p10 $p90 [expr {$w ? "written to out/clk_lat_$corner.txt" : "not written (setup-only session)"}]]
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
proc qb_pt_clk_tran {} {
    set_max_transition $::env(QC_CLK_TRAN_MAX) -clock_path [all_clocks]
    puts "QB_PT_CLK_TRAN clock-network max_transition $::env(QC_CLK_TRAN_MAX) ns on [sizeof_collection [all_clocks]] clocks (QC_CLK_TRAN_MAX)"
}
qb_pt_clk_tran
proc qb_pt_drv {fh} {
    redirect -variable t { report_constraint -max_transition -all_violators -nosplit }
    redirect -variable c { report_constraint -max_capacitance -all_violators -nosplit }
    set cp [get_clock_network_objects -type pin -include_clock_gating_network]
    foreach p [concat [get_object_name $cp] [get_object_name [get_attribute [all_clocks] sources]]] { set ck($p) 1 }
    set nd 0; set nc 0
    # ([ \t], not \s: \s also matches the newline, and the header's dash line then swallowed the first violator line)
    foreach {- p} [regexp -all -line -inline {^[ \t]*(\S+)[ \t].*VIOLATED} $t] { if {[info exists ck($p)]} { incr nc } else { incr nd } }
    set w 0.0
    foreach a {actual_rise_transition_max actual_fall_transition_max} {
        foreach x [get_attribute -quiet $cp $a] { if {[string is double -strict $x] && $x > $w} { set w $x } }
    }
    set mc [regexp -all -line {VIOLATED} $c]
    puts $fh [format "drv max_transition_violators %d max_capacitance_violators %d (design max_transition %s) clock_max_transition_violators %d (clock network %d pins, worst %.4f ns, limit QC_CLK_TRAN_MAX %s)" \
        $nd $mc [get_attribute [current_design] max_transition] $nc [sizeof_collection $cp] $w $::env(QC_CLK_TRAN_MAX)]
    return "max_transition $nd max_capacitance $mc clock_max_transition $nc"
}
proc qb_pt_async {fh} {
    redirect -variable r { report_constraint -recovery -all_violators -nosplit }
    redirect -variable m { report_constraint -removal -all_violators -nosplit }
    set l "recovery [regexp -all -line {VIOLATED} $r] removal [regexp -all -line {VIOLATED} $m]"
    puts $fh "async $l (register async set / clear pins [sizeof_collection [all_registers -async_pins]])"
    return $l
}
proc qb_pt_check_count {check} {
    redirect -variable t { check_timing -override_defaults $check }
    if {[regexp {check_timing succeeded} $t]} { return 0 }
    set n 0; foreach {- v} [regexp -all -inline {There (?:are|is) (\d+)} $t] { incr n $v }
    return [expr {$n ? $n : -1}]
}
proc qb_pt_coverage {fh} {
    set leaf [get_pins -quiet -hierarchical * -filter "is_hierarchical==false"]
    # constants: tie cells (constant output, no input pin) and the input pins on their nets; anything else is a stray
    set cv [filter_collection $leaf "defined(case_value)"]
    set src {}
    foreach_in_collection p [filter_collection $cv "direction==out"] {
        if {![sizeof_collection [get_pins -quiet -of_objects [get_cells -of_objects $p] -filter "direction==in"]]} { append_to_collection src $p }
    }
    set tied [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments -of_objects $src] -filter "direction==in"]
    set stray [remove_from_collection $cv [add_to_collection $src $tied]]
    foreach c [get_object_name [get_cells -quiet -of_objects $tied]] { set tc($c) 1 }
    # disabled arcs: expected = flag p / C (propagated constant, conditional arc) on a cell with a tie-driven input
    redirect -variable dis { report_disable_timing -nosplit }
    array set nf {p 0 C 0}; set bad 0; set loopf 0; set body 0
    foreach l [split $dis "\n"] {
        if {[string match "---*" $l]} { set body 1; continue }
        if {!$body || [string trim $l] eq "" || [string trim $l] eq "1"} continue
        if {![regexp {^(\S+)\s+\S+\s+\S+\s+\S+\s+([cCdflLmpuU])(?:\s|$)} $l -> cell f]} { incr bad; continue }
        if {$f eq "l" || $f eq "L"} { incr loopf; continue }
        if {($f eq "p" || $f eq "C") && [info exists tc($cell)]} { incr nf($f) } else { incr bad }
    }
    # nets with a load (leaf input pin, output port) and no driver (leaf output pin, input port): floating inputs
    foreach {v pd qd} {D "direction==out || direction==inout" "direction==in || direction==inout" L "direction==in" "direction==out"} {
        set $v [add_to_collection -unique [get_nets -quiet -top_net_of_hierarchical_group -segments -of_objects [filter_collection $leaf $pd]] \
            [get_nets -quiet -top_net_of_hierarchical_group -segments -of_objects [get_ports -quiet * -filter $qd]]]
    }
    set fl [remove_from_collection $L $D]
    set regc [all_registers -clock_pins]
    set r(unconstrained_endpoints) [qb_pt_check_count unconstrained_endpoints]
    set r(unclocked_register_pins) [sizeof_collection [filter_collection $regc "undefined(clocks)"]]
    set r(loops) [expr {[set n [qb_pt_check_count loops]] < 0 ? -1 : $n + $loopf}]
    set r(unexpected_disabled_arcs) [expr {$bad + [sizeof_collection $stray]}]
    set r(floating_nets) [sizeof_collection $fl]
    puts $fh "coverage register_clock_pins [sizeof_collection $regc] constants: tie_cells [sizeof_collection $src] tied_input_pins [sizeof_collection $tied] on [array size tc] cells, stray_constant_pins [sizeof_collection $stray]; disabled_arcs p $nf(p) C $nf(C) on those cells, other $bad loop_breaking $loopf; nets with_driver [sizeof_collection $D] with_load [sizeof_collection $L] floating [sizeof_collection $fl] [lrange [get_object_name $fl] 0 2]"
    set l {}; foreach k {unconstrained_endpoints unclocked_register_pins loops unexpected_disabled_arcs floating_nets} { lappend l $k $r($k) }
    puts $fh "coverage_gate $l"
    puts "QB_PT_SIGNOFF $l"
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
proc qb_pt_si_checks {fh rpt {noise_state {}}} {
    # the clock pulse checks are timing results: before the noise state, which changes the port drivers
    redirect -variable w { report_constraint -min_pulse_width -all_violators -nosplit }
    redirect -variable p { report_constraint -min_period -all_violators -nosplit }
    redirect ${rpt}_pulse.rpt { puts $w; puts $p }
    set l "min_pulse_width [regexp -all -line {VIOLATED} $w] min_period [regexp -all -line {VIOLATED} $p]"
    if {[llength $noise_state]} {
        puts $fh "noise_state [uplevel #0 $noise_state]"
        append l " noise_undriven_ports [qb_pt_check_count no_driving_cell]"
    }
    lassign [qb_pt_const_hold $::env(QC_CORNER)] hold cpins
    update_noise
    redirect -variable n { report_noise -all_violators -nosplit }
    redirect ${rpt}_noise.rpt { puts $n }
    # driver pins PrimeTime holds with no model at all (check_noise "none", both regions): 0 or the noise count is not evidence
    redirect -variable cn { check_noise -include {noise_driver} }
    set none [expr {[regexp -line {^\s*none\s+(\d+)\s+(\d+)\s*$} $cn -> a b] ? $a + $b : -1}]
    puts $fh "noise_hold constant drivers $hold; on their [sizeof_collection $cpins] load pins: [lindex [qb_pt_noise_pins $cpins] 1]"
    set l "noise [regexp -all -line {^\s*\S+ \(\S+\)\s+[-0-9.]+\s+[-0-9.]+\s+[-0-9.]+\s*$} $n] $l noise_undriven_pins $none"
    puts $fh "signoff $l"
    puts "QB_PT_SIGNOFF $l"
}
proc qb_pt_const_hold {corner} {
    set rec {}; set pins {}
    foreach l [split [exec $::env(QC_PY) -I $::QB_PT_DIR/lib_hold_res.py $::QC_LIBDIR/$::QC_LIB($corner).lib] "\n"] {
        lassign $l cell pin lv r
        set drv [get_pins -quiet -of_objects [get_cells -quiet -hierarchical -filter "ref_name==$cell"] -filter "lib_pin_name==$pin"]
        if {![sizeof_collection $drv]} continue
        # (both rails: the opposite state never occurs on a constant net, the value there only completes check_noise's count)
        foreach rail {low high} { foreach region {above below} { set_steady_state_resistance -$region -$rail $r [get_lib_pins */$cell/$pin] } }
        append_to_collection pins [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments -of_objects $drv] -filter "direction==in"]
        lappend rec "$cell/$pin [sizeof_collection $drv] x $lv $r"
    }
    return [list "[join $rec {, }] (steady-state resistance = library intrinsic_resistance, library unit)" $pins]
}
proc qb_pt_noise_pins {pins} {
    set viol 0; set txt {}
    foreach r {above_low below_high} {
        set w 0.0; set wp -; set n 0
        foreach_in_collection p $pins {
            set h [lindex [get_attribute -quiet $p si_noise_total_bump_$r] 0]   ;# {height width}
            if {![string is double -strict $h]} continue
            incr n; if {$h > $w} { set w $h; set wp [get_object_name $p] }
            set s [lindex [get_attribute -quiet $p si_noise_slack_$r] 0]
            if {[string is double -strict $s] && $s < 0} { incr viol }
        }
        lappend txt [format "%s %d analysed, worst bump %.3f V at %s" $r $n $w $wp]
    }
    return [list $viol "[sizeof_collection $pins] load pins: [join $txt {; }]; violators $viol"]
}
