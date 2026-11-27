# PrimeTime helpers shared by the sign-off / ETM scripts (signoff/pt/blk.tcl + its blocks col_blk.tcl / rgr_blk.tcl,
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
#                             <dir>/out/clk_lat_<corner>.txt (the block's clock latency for the chip top), by a
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
#   qb_pt_clk_tran            the ONE clock-network transition limit (R92, PI decision; QC_CLK_TRAN_MAX of
#                             common/limits.txt, common/limits.tcl qb_limit, R99): set_max_transition -clock_path on every clock, applied when sourced, so the
#                             sign-off scripts and the DMSA ECO setup (drv_eco.tcl sources the block script) check and
#                             fix the clock network against it (before: the 0.5 ns design limit only; CTS builds to 0.15)
#   qb_pt_drv <fh>            sign-off DRV line: max-transition violators split into data pins and clock-network pins
#                             (get_clock_network_objects + the clock sources; the latter against QC_CLK_TRAN_MAX, with
#                             the worst clock-network transition) and max-capacitance violators; returns "max_transition
#                             N max_capacitance N clock_max_transition N" (a QB_PT_SIGNOFF gate line, blk.tcl)
#   qb_pt_async <fh>          recovery / removal violators (checks of asynchronous set / clear pins; report_constraint
#                             -recovery / -removal -all_violators): constraint types of their own, outside the -max_delay /
#                             -min_delay reports the setup / hold counts read.  The clock-gating checks are inside those
#                             ([M] r91b ss / ff, every check made to fail: the 227 clock_gating_setup / _hold endpoints
#                             of the ICG E pins, group **clock_gating_default**, are 227 of the 31527 -max_delay / -min_delay
#                             violators).  r91b has no async set / clear pin (all_registers -async_pins 0), so these counts
#                             guard a future one.  "async ..." line to fh; returns "recovery N removal N" (QB_PT_SIGNOFF)
#   qb_pt_async_count         the counts alone: "recovery N removal N" (qb_pt_async; the ECO's state, drv_eco.tcl)
#   qb_pt_check_count <check> violations of one check_timing check: 0 on "check_timing succeeded", else the sum of its
#                             "There are N" counts, -1 if it reports neither (a gate never passes on an unread report)
#   qb_pt_coverage <fh>       coverage gates (R92): what the checks above do NOT time must be explained by the design.
#                             "coverage ..." lines to fh and QB_PT_SIGNOFF counts (common/env.sh qb_pt fails on non-zero):
#                             unconstrained_endpoints (check_timing), unclocked_inputs (qb_pt_unclocked_inputs: input
#                             ports without a clock-relative input delay but the declared untimed ones, R109),
#                             unclocked_register_pins (register clock pins no
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
#   qb_pt_noise_viol <report> the violators of a report_noise -all_violators -nosplit report (every listed pin line counts;
#                             qb_pt_si_checks, the ECO's noise counts signoff/pt/drv_eco.tcl)
#   qb_pt_noise_pins <pins>   after update_noise: {violators text unanalysed} of the given load pins from their si_noise_*
#                             pin attributes (above_low and below_high: pins PrimeTime analysed in detail, worst total
#                             bump, negative slacks; unanalysed: pins on a net with an aggressor and no bump, see the proc)
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
#                             (constraints.sdc qb_max_tran) as its input transition, and the tables are
#                             characterised up to that limit (extract_model_{data,clock}_transition_limit, default 5 ns).
#                             Output load index (R71): extract_model_capacitance_limit = the largest library
#                             max_capacitance of the cells driving the output ports (unset it is 64 pF, MEXT-6; R71 [M]
#                             r68 ss: 17 driver lib pins, 0.033 .. 0.790 pF).  The ETM tables start at 0 ns slew (R71 [M]
#                             index_1 0, 0.0311 .. 0.5), below the library's 0.0046 ns: the RC-011 extrapolation
#                             warnings of an ETM log are those zero-slew index points on the first cells behind the
#                             ports (r68 ss: slews 0.0001 .. 0.0004 ns)
#   qb_etm_ref <file>         the netlist reference of the session's ETM, read by signoff/etm/etmcheck.py (R98):
#                             first line "QB_ETM_REF period <P> max_transition <mt>" (the one clock's period, the
#                             design max_transition of qb_etm_context), then "<port> <in|out|inout> <cap pF>" per port:
#                             the port net's total_capacitance_max for an input (= the ETM input pin capacitance), its
#                             wire_capacitance_max for an output (= the ETM output pin capacitance; R98 [M] r97x wcl:
#                             all 12354 ports equal to the Liberty's 6 decimals)
#   OCV derate late 1.05 / early 0.95 on cell + net delays (common/derate.tcl, the same as the ICC2 timer), applied when
#   sourced (after the caller's constraints)
set ::QB_PT_DIR [file normalize [file dirname [info script]]]
source [file normalize [file dirname [info script]]/../../common/limits.tcl]
set_app_var timing_crpr_threshold_ps 1
set_app_var si_enable_analysis true
# DRV on case-constant nets too (R100; [M] hunt on a06c97, col s96b ss: report_constraint max_capacitance 4 vs 5 pins over
# their limit by the pin attributes): PrimeTime leaves tie / constant nets out of the max_capacitance / max_transition
# checks unless these are true.  Every PrimeTime session of the flow (sign-off, DMSA ECO scenarios, ETMs) sources this file.
set_app_var timing_enable_max_capacitance_set_case_analysis true
set_app_var timing_enable_max_transition_set_case_analysis true
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
# qb_pt_ann_rows <report_annotated_parasitics text>: {pin_to_pin N driverless N loadless N} = the Not Annotated counts of
# those rows (internal + boundary), -1 where the row pair is missing (qb_pt_ann; the ECO's pre-fix record, drv_eco.tcl)
proc qb_pt_ann_rows {ann} {
    set out {}
    foreach k {pin_to_pin driverless loadless} r {{Pin to pin} Driverless Loadless} {
        set n 0; set m 0
        foreach {- v} [regexp -all -line -inline "^\\s*- $r nets\\s*\\|(?:\\s*\\d+\\s*\\|){5}\\s*(\\d+)\\s*\\|" $ann] { incr n $v; incr m }
        lappend out $k [expr {$m == 2 ? $n : -1}]
    }
    return $out
}
proc qb_pt_ann {} {
    redirect -variable ann { report_annotated_parasitics }
    array set n [qb_pt_ann_rows $ann]
    puts "QB_PT_SIGNOFF unannotated_pin_to_pin $n(pin_to_pin)"
    if {![regexp {\n\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|} $ann -> tot rc cc na]} { return NA }
    return "total $tot rc_network $rc coupled_network $cc not_annotated $na (driverless $n(driverless) loadless $n(loadless) pin_to_pin $n(pin_to_pin))"
}
set ::QB_PT_ANY_SLACK 1e9
proc qb_pt_paths {rpt args} {
    redirect $rpt { foreach a $args { report_timing -slack_lesser_than $::QB_PT_ANY_SLACK -nosplit {*}$a } }
}
proc qb_pt_clk_tran {} {
    set_max_transition [qb_limit QC_CLK_TRAN_MAX] -clock_path [all_clocks]
    puts "QB_PT_CLK_TRAN clock-network max_transition [qb_limit QC_CLK_TRAN_MAX] ns on [sizeof_collection [all_clocks]] clocks (QC_CLK_TRAN_MAX)"
}
qb_pt_clk_tran
# The counts below read reports captured with redirect.  An error of such a report command is NOT lost: its message goes
# to the variable, not the log, but PrimeTime's "Diagnostics summary: N errors" at exit counts it and common/env.sh
# qb_pt fails the session on it (diagnostics_errors).  [M] R100: 9 errors in that line against 4 visible '^Error' log
# lines, = get_message_info -error_count; [M] R104 tau14: two seeded failing reports under redirect, 0 '^Error' log
# lines, "Diagnostics summary: 2 errors", evidence bad.
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
        $nd $mc [get_attribute [current_design] max_transition] $nc [sizeof_collection $cp] $w [qb_limit QC_CLK_TRAN_MAX]]
    return "max_transition $nd max_capacitance $mc clock_max_transition $nc"
}
proc qb_pt_async_count {} {
    redirect -variable r { report_constraint -recovery -all_violators -nosplit }
    redirect -variable m { report_constraint -removal -all_violators -nosplit }
    return "recovery [regexp -all -line {VIOLATED} $r] removal [regexp -all -line {VIOLATED} $m]"
}
proc qb_pt_async {fh} {
    set l [qb_pt_async_count]
    puts $fh "async $l (register async set / clear pins [sizeof_collection [all_registers -async_pins]])"
    return $l
}
proc qb_pt_check_count {check} {
    redirect -variable t { check_timing -override_defaults $check }
    if {[regexp {check_timing succeeded} $t]} { return 0 }
    set n 0; foreach {- v} [regexp -all -inline {There (?:are|is) (\d+)} $t] { incr n $v }
    return [expr {$n ? $n : -1}]
}
# qb_pt_unclocked_inputs: {N text}, N = the input ports without a clock-relative input delay on every edge (min / max x
# rise / fall: report_port -input_delay, a "--" field or no related clock) but the clock sources and the deliberate
# untimed inputs ::QB_UNTIMED_INPUTS (common/constraints.sdc: rst_n, a false path), + every declared name that is no
# input port; -1 when the report does not list every input port once (unparsed).  R109; hunt round 12: the coverage
# counted unconstrained endpoints only, so an input the IO budget missed started no timed path.  check_timing
# no_input_delay is no such check: [M] tau14 PrimeTime on rgr rgf51c41ba ss, remove_input_delay x[0] -> "check_timing
# succeeded" while report_port listed x[0] "--" and get_timing_paths -from x[0] found no path.
proc qb_pt_unclocked_inputs {} {
    set ins [get_ports -quiet * -filter "direction==in || direction==inout"]
    if {![sizeof_collection $ins]} { return [list 0 "no input port"] }
    redirect -variable t { report_port -input_delay -nosplit $ins }
    set seen {}; set nd {}
    # (rows "<port> <min rise> <min fall> <max rise> <max fall> <clock> <pin>" after the dash line; [ \t], not \s: \s
    # also matches the newline)
    foreach {- p f} [regexp -all -inline -line {^(\S+)((?:[ \t]+\S+){6})[ \t]*$} [regsub {^.*?\n-{20,}\n} $t {}]] {
        lappend seen $p
        lassign $f a b c d ck
        if {"--" in [list $a $b $c $d $ck]} { lappend nd $p }
    }
    set want [lsort [get_object_name $ins]]
    if {[lsort $seen] ne $want} { return [list -1 "unparsed: report_port -input_delay listed [llength $seen] of [llength $want] input ports"] }
    set ck [get_object_name [get_attribute -quiet [get_clocks -quiet *] sources]]
    set dl [expr {[info exists ::QB_UNTIMED_INPUTS] ? $::QB_UNTIMED_INPUTS : {}}]
    set u [lmap w $nd { if {$w in $ck || $w in $dl} continue; set w }]
    lappend u {*}[lmap w $dl { if {$w in $want} continue; string cat "declared_not_an_input:" $w }]
    return [list [llength $u] "without input delay [llength $nd] ([lrange $nd 0 4]), clock sources ($ck), declared untimed ($dl), unexplained ([lrange $u 0 4])"]
}
proc qb_pt_coverage {{fh ""}} {
    set leaf [get_pins -quiet -hierarchical * -filter "is_hierarchical==false"]
    # constants: tie cells (constant output, no input pin) and the input pins on their nets; anything else is a stray.
    # (R109; hunt round 12: on a design without constants, e.g. rgr, the collection commands below got empty collections
    # and PrimeTime warned SEL-003 twice per session: each step only on a non-empty collection)
    set cv [filter_collection $leaf "defined(case_value)"]
    set src {}; set tied {}; set stray {}
    if {[sizeof_collection $cv]} {
        foreach_in_collection p [filter_collection $cv "direction==out"] {
            if {![sizeof_collection [get_pins -quiet -of_objects [get_cells -of_objects $p] -filter "direction==in"]]} { append_to_collection src $p }
        }
        if {[sizeof_collection $src]} { set tied [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments -of_objects $src] -filter "direction==in"] }
        set ex [expr {[sizeof_collection $src] ? [add_to_collection $src $tied] : {}}]
        set stray [expr {[sizeof_collection $ex] ? [remove_from_collection $cv $ex] : $cv}]
    }
    if {[sizeof_collection $tied]} { foreach c [get_object_name [get_cells -quiet -of_objects $tied]] { set tc($c) 1 } }
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
    lassign [qb_pt_unclocked_inputs] r(unclocked_inputs) ui
    set r(unclocked_register_pins) [expr {[sizeof_collection $regc] ? [sizeof_collection [filter_collection $regc "undefined(clocks)"]] : 0}]
    set r(loops) [expr {[set n [qb_pt_check_count loops]] < 0 ? -1 : $n + $loopf}]
    set r(unexpected_disabled_arcs) [expr {$bad + [sizeof_collection $stray]}]
    set r(floating_nets) [sizeof_collection $fl]
    set l {}; foreach k {unconstrained_endpoints unclocked_inputs unclocked_register_pins loops unexpected_disabled_arcs floating_nets} { lappend l $k $r($k) }
    if {$fh ne ""} {
        puts $fh "coverage inputs $ui"
        puts $fh "coverage register_clock_pins [sizeof_collection $regc] constants: tie_cells [sizeof_collection $src] tied_input_pins [sizeof_collection $tied] on [array size tc] cells, stray_constant_pins [sizeof_collection $stray]; disabled_arcs p $nf(p) C $nf(C) on those cells, other $bad loop_breaking $loopf; nets with_driver [sizeof_collection $D] with_load [sizeof_collection $L] floating [sizeof_collection $fl] [expr {[sizeof_collection $fl] ? [lrange [get_object_name $fl] 0 2] : ""}]"
        puts $fh "coverage_gate $l"
        puts "QB_PT_SIGNOFF $l"
    }
    return $l
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
proc qb_etm_ref {file} {
    set ck [all_clocks]
    if {[sizeof_collection $ck] != 1} { error "qb_etm_ref: [sizeof_collection $ck] clocks, the ETM check needs exactly one period" }
    set f [open $file w]
    puts $f [format "QB_ETM_REF period %.6f max_transition %.6f" [get_attribute $ck period] [get_attribute [current_design] max_transition]]
    foreach_in_collection q [get_ports *] {
        set d [get_attribute $q direction]
        set c [get_attribute [get_nets -of_objects $q] [expr {$d eq "out" ? "wire_capacitance_max" : "total_capacitance_max"}]]
        puts $f [format "%s %s %.6f" [get_object_name $q] $d $c]
    }
    close $f
}
# qb_pt_pulse [<rpt>]: "min_pulse_width N min_period N" violators (report_constraint -all_violators), both reports to
# <rpt>_pulse.rpt when given (qb_pt_si_checks; the ECO's pre-fix record, signoff/pt/drv_eco.tcl)
proc qb_pt_pulse {{rpt ""}} {
    redirect -variable w { report_constraint -min_pulse_width -all_violators -nosplit }
    redirect -variable p { report_constraint -min_period -all_violators -nosplit }
    if {$rpt ne ""} { redirect ${rpt}_pulse.rpt { puts $w; puts $p } }
    return "min_pulse_width [regexp -all -line {VIOLATED} $w] min_period [regexp -all -line {VIOLATED} $p]"
}
# qb_pt_noise_undriven_pins (after update_noise): driver pins PrimeTime holds with no model at all (check_noise "none",
# both regions; 0, or the noise count is not evidence); -1 when the report has no such row
proc qb_pt_noise_undriven_pins {} {
    redirect -variable cn { check_noise -include {noise_driver} }
    return [expr {[regexp -line {^\s*none\s+(\d+)\s+(\d+)\s*$} $cn -> a b] ? $a + $b : -1}]
}
proc qb_pt_si_checks {fh rpt {noise_state {}}} {
    # the clock pulse checks are timing results: before the noise state, which changes the port drivers
    set l [qb_pt_pulse $rpt]
    if {[llength $noise_state]} {
        puts $fh "noise_state [uplevel #0 $noise_state]"
        append l " noise_undriven_ports [qb_pt_check_count no_driving_cell]"
    }
    lassign [qb_pt_const_hold $::env(QC_CORNER)] hold cpins
    update_noise
    redirect -variable n { report_noise -all_violators -nosplit }
    redirect ${rpt}_noise.rpt { puts $n }
    set none [qb_pt_noise_undriven_pins]
    puts $fh "noise_hold constant drivers $hold; on their [sizeof_collection $cpins] load pins: [lindex [qb_pt_noise_pins $cpins] 1]"
    set l "noise [qb_pt_noise_viol $n] $l noise_undriven_pins $none"
    puts $fh "signoff $l"
    puts "QB_PT_SIGNOFF $l"
}
# qb_pt_noise_viol: validated on real violators, [M] col r94 ml_rcb: its report_noise -all_violators listed 4 violator
# rows and the count was "noise 4"
proc qb_pt_noise_viol {rpt} { regexp -all -line {^\s*\S+ \(\S+\)\s+[-0-9.]+\s+[-0-9.]+\s+[-0-9.]+\s*$} $rpt }
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
# qb_pt_noise_pins <pins>: {violators text unanalysed} of load pins after update_noise.  A pin is analysed in a region when
# PrimeTime gave it a bump (si_noise_total_bump_*); unanalysed = pins on a net with an aggressor (number_of_aggressors > 0)
# that lack a bump in either region: PrimeTime's default noise analysis type (violators) analyses in detail only the nets
# it deems potentially violating, the others get no bump at all (NOISE-015), so their slack is no evidence (R100)
proc qb_pt_noise_pins {pins} {
    set viol 0; set txt {}; set un 0; set cp 0
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
    foreach_in_collection p $pins {
        set a [get_attribute -quiet [get_nets -of_objects $p] number_of_aggressors]
        if {![string is integer -strict $a] || $a == 0} continue
        incr cp
        foreach r {above_low below_high} {
            if {![string is double -strict [lindex [get_attribute -quiet $p si_noise_total_bump_$r] 0]]} { incr un; break }
        }
    }
    return [list $viol "[sizeof_collection $pins] load pins: [join $txt {; }]; on nets with aggressors $cp, of them unanalysed $un; violators $viol" $un]
}
