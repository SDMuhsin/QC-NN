# PrimeTime ECO of a routed block.  The design setup is the block's own sign-off script QB_PT_SCRIPT (signoff/pt/
# col_blk.tcl, rgr_blk.tcl) up to its design setup (netlist, SDC, SPEF, propagated clock, IO budget: the script
# returns there when ::QB_PT_SETUP_ONLY exists), plus the shared dont_use list (site.tcl QC_DONT_USE, read by DC too).
# One round of the sign-off ECO loop (common/block.sh eco, R92) at every corner of QB_ECO_CORNERS together (pt_shell
#   -multi_scenario, DMSA; ICC2, R56 results/r56.md): one scenario process per corner, physically aware (open_site, every
#   pass: QB_ECO_PMODE below) on the ICC2 design library QB_ECO_NLIB / block QB_ECO_BLOCK (required, R81);
#     0. pre-fix state of every corner at the sign-off criterion -> eco_summary.txt "before" lines and "prefix_total n"
#        (setup + hold + recovery + removal + max_transition + max_capacitance + noise violators over all corners, zero
#        margin: every violator count the sign-off gates, signoff/pt/blk.tcl QB_PT_SIGNOFF; the clock-network DRV counts
#        are part of max_transition / max_capacitance; noise counted as the sign-off counts it, in the block's noise
#        state, qb_eco_noise_state; + the column's act_noise violators).  Then "prefix_unfixable m": the corner:check
#        counts of the sign-off's other gates (min pulse width / period, unannotated pin-to-pin, coverage, undriven noise
#        drivers, unanalysed act pins: qb_eco_signoff_count / _noise_count) that are not 0, which no pass below fixes:
#        m > 0 ends the round with no change list (eco none: FAIL), and the loop stops (R103).  n = 0 and m = 0: the
#        block has converged (the post step's PrimeTime gates as far as this session sees them), no change list.
#        QB_ECO_CHECK=1 (the loop's check after its last round): state only, no change list either.  Also "prefix_tns t"
#        (R108): the setup + hold total negative slack (ns) of the same violators, summed over the corners, which the
#        loop's stop rule reads beside the count (common/block.sh blk_eco_progress).
#     1. fix_eco_drc max_transition, then max_capacitance, then crosstalk noise (R67; update_noise in the setup), each
#        physically aware only (R81, qb_eco_drc); max_transition / max_capacitance also in the clock network (R75,
#        qb_eco_clock_buffers), physically aware with the clock-network physical data (R81)
#     2. fix_eco_timing -type setup (size_cell, insert_buffer of qb_eco_buffers: every BUFFD* not dont_use; R67, R69).
#        Fix margin QC_ECO_SETUP_MARGIN (ns; a committed limit of common/limits.txt, R108, PI decision): -setup_margin m
#        -slack_lesser_than m, every endpoint below m fixed to m, as the hold margin below.  Why [M] rgr rg039bd31a /
#        rg1fe9be2a: at zero margin PT fixed each violator to 0.2-10 ps of predicted slack, the ICC2 implementation of
#        the change list then cost 3.7-12 ps per endpoint (median -10.6; size_cell moves of 0.6-1.4 um rerouted, 3-5 ps
#        neighbour coupling), and 13 / 2 endpoints landed below zero.  0.015 covers that measured error (max 12 ps) once
#        add_buffer_on_route buffers stay on their route point (flow/icc2/common.tcl qb_eco_route_resolve, R108; the
#        -25 to -30 ps case) and no sized cell is moved by ICC2's legaliser (QB_ECO_PMODE).  Convergence stays at zero
#        margin (prefix_total).
#     3. fix_eco_timing -type hold (size_cell, insert_buffer of common/lib_cells.tcl qb_hold_cells: the list ICC2 hold
#        fixing uses, R84); PT keeps setup / DRV of every scenario clean.  Guard-band QC_ECO_HOLD_MARGIN (ns, default
#        0.005; R92, PI decision): -hold_margin m -slack_lesser_than m.  PT Q-2019.12-SP2 man: -hold_margin "affects the
#        target amount of timing slack to achieve during hold fixing" (positive = overfixing), but "for paths not
#        already selected for hold fixing (by default, paths with zero or better slack), there is no attempt to change
#        the path to meet the margin"; -slack_lesser_than selects "the paths with a slack worse than the specified
#        slack limit" (default 0).  Both together: every endpoint below m is fixed to m.  Why [M] r91b: 264 hold
#        endpoints within 5 ps of zero at wcl, and the ECO route moved 2 untouched ones to -0.04 / -0.09 ps.
#     4. fix_eco_drc noise again (R85): the hold pass does not keep noise.
#     5. setup and hold again as 2. / 3., in the timing state; then the end noise state (in the noise state).
#   Timing is fixed and judged in the timing state only (R96, design choice).  A noise pass runs in the block's noise
#   state, where the column's act ports carry the QB5_FT driving cell and port load instead of their measured input
#   transition: what PrimeTime times there is not sign-off timing.  So no noise pass gets timing margins (-setup_margin
#   / -hold_margin would preserve, or spend, slack of that timing: on the act -> u_pe paths it could spend real hold
#   slack), and after the last noise pass setup and hold are repaired in the timing state (step 5; hold to its guard-
#   band again).  Noise the repair may disturb is in the end record and, at the sign-off criterion, in the next round's
#   prefix_total: the loop's convergence judges it, never a margin in the wrong state.
#   Fix guard-bands of DRV and noise (R92 follow-up, PI decision; the analogue of the hold margin).  Why [M] r91b: a zero-
#   margin fix leaves pins at the limit (12 driver pins above 0.495 of 0.500 ns at ss) and the round's own ECO route tips
#   them (11 max_transition pins, 1 noise victim, none touched by the ECO).  fix_eco_drc has no fixing margin (man:
#   -slack_lesser_than takes a positive limit only for -type delta_delay; -setup_margin / -hold_margin preserve timing):
#   * max_transition / max_capacitance, QC_ECO_DRV_MARGIN (common/env.sh): for the duration of the type's fix passes
#     every pin at or over limit x (1 - margin) gets that value as a pin-level limit, removed right after (qb_eco_guard).
#   * noise, QC_ECO_NOISE_MARGIN: PrimeTime's own noise derate for the duration of the pass, bump height x 1 / (1 -
#     margin) on the design (set_noise_derate -height_factor), reset to 1.0 right after (qb_eco_noise_guard).
#   Every state line, prefix_total and the loop's convergence are at the sign-off limits (no guard active); the summary
#   has, per pass and corner, the pins over the limit and in the band [limit x (1 - margin), limit] before and after the
#   fix (noise: the violators under the guard before and after the fix, qb_eco_noise_guard).
#   Noise passes and counts run in the block's noise-only analysis state (R92, sign-off: ::QB_PT_NOISE_STATE of the
#   block's PrimeTime script, the column's act ports with a holding driver) and with the constant drivers' holding model
#   (signoff/pt/common.tcl qb_pt_const_hold), as the sign-off's noise check; timing counts and passes in the timing state.
#   Writes <QC_PNR_OUT>/out/eco/pt_eco.tcl (icc2tcl, applied by flow/icc2/eco.tcl), pt_eco_cells.txt
#   (its new cells, R90: qb_eco_cells_write), eco_summary.txt; with a change list also the lines "eco_changes n" (its
#   change commands, common/eco_changes.tcl qb_eco_change_count) and "eco_residual" (R116: the end state's non-zero
#   corner:check counts of prefix_total's checks), and pt_eco_ndr.txt with the line "eco_ndr_nets m" (the nets of the
#   noise victims the last noise pass could not fix, which ICC2 eco.tcl routes with a spacing rule: qb_eco_ndr_nets);
#   n = m = 0 with a non-zero prefix_total ends the loop before ICC2 (common/block.sh blk_eco)
#   (lines "<tag> <corner> <record>", in the log as QB_ECO_STATE lines: timing counts before / drc / setup / hold /
#   post_noise_setup / post_noise_hold [the end state] = setup / hold / recovery / removal violators, max_tran / max_cap
#   pins (of them in the clock network), hold / setup endpoints inside their fix margin [0, margin) (hold_band /
#   setup_band), setup / hold total negative slack (setup_tns / hold_tns, ns); end_noise; per fix pass the guard
#   records <pass>_guard_on / _off = pins over the limit and in the fix band [noise: violators under the guard], and
#   noise_pre / noise_post = noise violators in the noise state; ECO size), the unfixable reasons of every pass (<type>_unfixable*,
#   drc_<type>[_clock]_unfixable*).
# No physical_mode none anywhere (R81, PI decision): R80 [M] the r79 clock-network pass without physical constraints
# upsized a FIXED CTS inverter in place (cts_inv_36669764 CKND8 -> CKND12), which then overlapped g_r_12 U23 (the LVS
# short).  ICC2 eco.tcl cannot legalise around an in-place-sized fixed cell, so a change PT cannot make physically is
# left unfixed and REPORTED (unfixable reasons + qb_eco_timing_count), never forced.
# Env: QC_PNR_OUT, QB_PT_SCRIPT and the variables that script reads (QC_TOP, QC_SDC, QC_PERIOD, ...), QB_ECO_CORES.
proc qb_eco_setup {corner} {
    set ::env(QC_CORNER) $corner
    set ::QB_PT_SETUP_ONLY 1
    uplevel #0 { source $::env(QB_PT_SCRIPT) }
    # site/pnr.tcl: decap / filler cells of set_eco_options; the dont_use list is site.tcl's (sourced by the PT script)
    uplevel #0 { source $::env(QC_FLOW)/site/pnr.tcl; source $::env(QC_FLOW)/../../qc18bacc/flow/common/lib_cells.tcl
        source $::env(QC_FLOW)/../../qc18bacc/flow/common/eco_changes.tcl }
    # clock-tree lib cells (common/lib_cells.tcl qb_clock_cells): the only sizing candidates of the clock-network pass (qb_eco_drc)
    define_user_attribute -type boolean -class lib_cell qb_clock_cell
    set_user_attribute -quiet [get_lib_cells [lmap g [qb_clock_cells] { string cat */ $g }]] qb_clock_cell true
    foreach p $::QC_DONT_USE { set c [get_lib_cells -quiet */$p]; if {[sizeof_collection $c]} { set_dont_use $c } }
    qb_dont_use_gate eco_$corner 1
    uplevel #0 { set eco_report_unfixed_reason_max_endpoints 1000 }
    # crosstalk noise of the sign-off (signoff/pt/common.tcl qb_pt_si_checks: constant drivers held by their library
    # resistance), fixed by fix_eco_drc -type noise
    puts "QB_ECO_CONST_HOLD $corner [lindex [qb_pt_const_hold $corner] 0]"
    update_noise
}
# ECO buffers: every BUFFD* lib cell the dont_use list allows (R69: the former hand list BUFFD2 / 4 / 8 left a 1.5 mm
# BUFFD16 HFS net at ml max_transition unfixable, reason D; with BUFFD12 / 16 allowed one BUFFD16 fixes it [M])
proc qb_eco_buffers {} {
    return [lsort -unique [lmap c [get_object_name [get_lib_cells -filter dont_use==false */BUFFD*]] { file tail $c }]]
}
# clock-network ECO buffers: the CTS buffers of site/pnr.tcl QC_PNR_CTS_BUF (cts.tcl) the dont_use list allows.  R75 [M]:
# ICC2 leaves a clock-gate output over its limit (CTS sizes the gate at zero slack on its estimate, detail clock routing
# adds the rest: r74 / r75 clk_gate_shd_reg_3 CKLNQD2 0.119 / 0.1185 pF at ss) and its post-route clock DRC fixing never
# resizes a clock gate (flow/icc2/cts.tcl); fix_eco_drc -cell_type clock_network fixes it (r74 ss: one CKBD4 after the gate).
proc qb_eco_clock_buffers {} {
    set b {}; foreach g $::QC_PNR_CTS_BUF { lappend b {*}[lmap c [get_object_name [get_lib_cells -quiet -filter dont_use==false */$g]] { file tail $c }] }
    return [lsort -unique $b]
}
# Physical mode of every fix pass (R108): open_site, PT places a new or sized cell only on free sites (filler / decap,
# set_eco_options -filler_cell_names).  [M] rgr rg4012628a (tau14) in occupied_site: PT sized cells over their real
# neighbours (u_lane/U114 INR2XD1 -> INR2XD4 at its own origin, 5.2 um wide where 1.8 um was free: over u_lane/U126 and
# ctmTdsLR_1_948; ctmTdsLR_1_954 AOI21D4 over ctmTdsLR_2_955 / _2_857), and ICC2's place_eco_cells -legalize_only then
# moved 34 of 86 changed cells, up to 7.0 um (U114 3.7 um: its fanin net n80 5.12 fF where PT timed 3.06, b_o_reg -34 ps
# against PT's +15.8; ctmTdsLR_2_955 0.2561 ns max_transition at ss): the loop stopped at round 2.  The same layout
# (copy at label route) in open_site: 4 cells moved, max 0.7 um, converged at round 2.
set ::QB_ECO_PMODE open_site
# DRV / noise fixing, physically aware only (QB_ECO_PMODE; R81, PI decision, header): what PT cannot fix in place or on
# free sites stays a reported violator (unfixable reasons <pfx>drc_<type>[_clock]*, qb_eco_timing_count), not a change
# without a location.  (R69 [M] had one port-driven noise victim, column s_rd[523], unfixable in occupied_site and fixed
# only without physical constraints: such a case is now reported for the PI.)
# -cell_type combinational (R116): PT Q-2019.12-SP2 man fix_eco_drc documents combinational | clock_network only, "Only
# combinational logic cells are resized. Sequential cells are not resized" (no option); the former {combinational
# sequential} was accepted silently and did the same ([M] r102 eco2 copy, ml_rcb: unfixable I Q and 0 commands both).
# A noise victim the pass cannot fix gets the spacing rule instead (qb_eco_ndr_nets).
# Clock-network DRV (cbufs given, DMSA master): physically aware too, with set_eco_options -physical_enable_clock_data
# in every scenario (qb_eco_phys; PT man fix_eco_drc "Clock Network Fixing": physically aware clock fixing needs it),
# so PT sees the clock cells' placement and never sizes a fixed clock cell into its neighbour; sizing restricted to
# the clock-tree lib cells (PT otherwise uses every alternative: r75 eco 1 [M] sized cts_inv_34929379 to INVD8;
# fix_eco_drc man: eco_alternative_cell_attribute_restrictions), set in the scenarios for this pass only.
proc qb_eco_drc {pfx bufs {cbufs {}} {types {max_transition max_capacitance noise}}} {
    set tag [string map [list [file dirname ${pfx}x]/ ""] $pfx]   ;# summary tag of the pass: "", "post_hold_", "<corner>_"
    foreach ty $types {
        if {$ty eq "noise"} {
            qb_eco_noise_state on
            qb_eco_all ${tag}noise_pre qb_eco_noise_count
            qb_eco_all ${tag}noise_guard_on {qb_eco_noise_guard on}
        } else { qb_eco_all ${tag}${ty}_guard_on "qb_eco_guard $ty on" }
        fix_eco_drc -type $ty -methods {size_cell insert_buffer} -buffer_list $bufs \
            -cell_type combinational -physical_mode $::QB_ECO_PMODE -verbose \
            -unfixable_reasons_prefix ${pfx}drc_$ty -unfixable_reasons_format text
        if {[llength $cbufs] && $ty ne "noise"} {
            remote_execute { set eco_alternative_cell_attribute_restrictions qb_clock_cell }
            fix_eco_drc -type $ty -methods {size_cell insert_buffer} -buffer_list $cbufs -cell_type clock_network \
                -physical_mode $::QB_ECO_PMODE -verbose -unfixable_reasons_prefix ${pfx}drc_${ty}_clock -unfixable_reasons_format text
            remote_execute { set eco_alternative_cell_attribute_restrictions "" }
        }
        if {$ty eq "noise"} {
            qb_eco_all ${tag}noise_guard_off {qb_eco_noise_guard off}
            qb_eco_all ${tag}noise_post qb_eco_noise_count
            qb_eco_noise_state off
        } else { qb_eco_all ${tag}${ty}_guard_off "qb_eco_guard $ty off" }
    }
}
# qb_eco_note <line> [<kind>]: a line of the round's record, eco_summary.txt (ECO loop) and the log (QB_ECO<_kind> <line>)
proc qb_eco_note {l {kind {}}} {
    puts "QB_ECO[expr {$kind eq "" ? "" : "_$kind"}] $l"
    if {[info exists ::QB_ECO_SF]} { puts $::QB_ECO_SF $l; flush $::QB_ECO_SF }
}
# qb_eco_all <tag> <command>: the command (it returns a one-line record) in every scenario process of the ECO loop; the
# records become the lines "<tag> <corner> <record>" (log: QB_ECO_STATE <line>); returns {corner record ...};
# error unless every corner returned one (a scenario that failed the command would otherwise only miss a line).
proc qb_eco_all {tag cmd} {
    set c "puts \"QB_ECO_REC \$::env(QC_CORNER) \[$cmd\]\""
    set cs $::env(QB_ECO_CORNERS); redirect -variable r { remote_execute -verbose $c }
    set out {}
    foreach l [split $r "\n"] { if {[regexp {QB_ECO_REC (\w+) (.*)$} $l -> k x]} { qb_eco_note "$tag $k $x" STATE; lappend out $k $x } }
    if {[llength $out] != 2 * [llength $cs]} { puts $r; error "QB_PT_ECO $tag: a record from [expr {[llength $out] / 2}] of [llength $cs] corners" }
    return $out
}
# qb_eco_sum <records of qb_eco_all> <keys>: the given values (counts, or slacks in ns) summed over the corners
proc qb_eco_sum {recs keys} {
    set t 0; foreach {c x} $recs { foreach k $keys { set t [expr {$t + [dict get $x $k]}] } }
    return $t
}
# The procs below run in a scenario process and return a record for qb_eco_all.
# qb_eco_timing_count: violators at the sign-off criterion (timing state, no guard active; recovery / removal:
# signoff/pt/common.tcl qb_pt_async_count, as the sign-off); setup_tns / hold_tns = the sum of the slacks of exactly
# those setup / hold violators (ns, R108); hold_band / setup_band = endpoints with 0 <= slack < the pass's fix margin
# QC_ECO_HOLD_MARGIN / QC_ECO_SETUP_MARGIN (the margin populations; not violators)
proc qb_eco_timing_count {} {
    redirect -variable s { report_constraint -max_delay -all_violators -nosplit -significant_digits 4 }
    redirect -variable h { report_constraint -min_delay -all_violators -nosplit -significant_digits 4 }
    redirect -variable t { report_constraint -max_transition -all_violators -nosplit }
    redirect -variable k { report_constraint -max_capacitance -all_violators -nosplit }
    set r "setup [regexp -all -line {VIOLATED} $s] hold [regexp -all -line {VIOLATED} $h] [qb_pt_async_count] max_tran [regexp -all -line {VIOLATED} $t] max_cap [regexp -all -line {VIOLATED} $k] clock_max_tran [qb_eco_clk_viol $t] clock_max_cap [qb_eco_clk_viol $k] cells [sizeof_collection [get_cells -hier -filter is_hierarchical==false]]"
    foreach {ty m} [list min $::env(QC_ECO_HOLD_MARGIN) max [qb_limit QC_ECO_SETUP_MARGIN]] {
        set b 0
        if {$m > 0} { foreach_in_collection p [get_timing_paths -delay_type $ty -max_paths 100000 -slack_lesser_than $m] { if {[get_attribute $p slack] >= 0} { incr b } } }
        append r [expr {$ty eq "min" ? " hold_band $b" : " setup_band $b"}]
    }
    return "$r setup_tns [qb_eco_tns $s] hold_tns [qb_eco_tns $h]"
}
# total negative slack of a report_constraint -all_violators report: the sum of the slack on every VIOLATED line (the lines
# qb_eco_timing_count counts), %.4f ns; error on a VIOLATED line without a slack before it
proc qb_eco_tns {rpt} {
    set n [regexp -all -line {VIOLATED} $rpt]; set v [regexp -all -inline -line {(-[0-9.]+)\s+\(VIOLATED} $rpt]
    if {[llength $v] != 2 * $n} { error "qb_eco_tns: [expr {[llength $v] / 2}] slacks on $n VIOLATED lines" }
    set t 0.0; foreach {- x} $v { set t [expr {$t + $x}] }
    return [format %.4f $t]
}
# qb_eco_signoff_count (timing state) / qb_eco_signoff_noise_count (noise state): the sign-off's other gate counts
# (signoff/pt/blk.tcl QB_PT_SIGNOFF; R103) with the same procs: min pulse width / min period, unannotated pin-to-pin nets,
# coverage (signoff/pt/common.tcl), then noise_undriven_ports / _pins and the block's noise-stage gates (qb_blk_hook
# noise_count: the column's act_noise / act_noise_unanalysed)
proc qb_eco_signoff_count {} {
    redirect -variable a { report_annotated_parasitics }
    return "[qb_pt_pulse] unannotated_pin_to_pin [dict get [qb_pt_ann_rows $a] pin_to_pin] [qb_pt_coverage]"
}
proc qb_eco_signoff_noise_count {} {
    set r "noise_undriven_ports [qb_pt_check_count no_driving_cell] noise_undriven_pins [qb_pt_noise_undriven_pins]"
    if {[llength [info procs qb_blk_hook]]} { append r " [qb_blk_hook noise_count]" }
    return [string trim $r]
}
# qb_eco_guard <max_transition|max_capacitance> on|off|scan: the DRV fix guard-band (header).  The pins at or over limit x
# (1 - QC_ECO_DRV_MARGIN), by the pin attributes report_constraint evaluates (man pin_attributes; r92 ss [M]: 84 pins over
# the transition limit = report_constraint's 84, a tightened limit on 334 pins -> 333 violators, removed -> 84 and every
# limit as before).  on: each gets limit x (1 - margin) as a pin-level limit; off: exactly those are removed; scan: count
# only.  The record is taken at the sign-off limits (before on / after off): over = pins over their limit (the constant
# pins too, which report_constraint lists since R100, signoff/pt/common.tcl; r92 ss [M] before: 8 against its 6), band = pins in [limit x
# (1 - margin), limit].
array set ::QB_ECO_DRV_ATTR {
    max_transition  {drc_actual_max_transition constraining_max_transition}
    max_capacitance {drc_actual_max_capacitance drc_constraining_max_capacitance}
}
set ::QB_ECO_GUARDED {}
proc qb_eco_guard {ty mode} {
    set m $::env(QC_ECO_DRV_MARGIN)
    if {$mode eq "on" && [llength $::QB_ECO_GUARDED]} { error "qb_eco_guard $ty on: [llength $::QB_ECO_GUARDED] pins still guarded" }
    if {$mode eq "off" && [llength $::QB_ECO_GUARDED]} {
        set g [get_pins -quiet $::QB_ECO_GUARDED]   ;# (by name: the fix passes edit the netlist in between)
        if {[sizeof_collection $g] != [llength $::QB_ECO_GUARDED]} { error "qb_eco_guard $ty off: [sizeof_collection $g] of [llength $::QB_ECO_GUARDED] guarded pins found" }
        remove_$ty $g; set ::QB_ECO_GUARDED {}
    }
    lassign $::QB_ECO_DRV_ATTR($ty) a l
    set P [get_pins -quiet -hierarchical -filter "defined($a) && defined($l)"]
    set over 0; set band 0; set i -1
    foreach x [get_attribute $P $a] y [get_attribute $P $l] {
        incr i
        if {$x > $y} { incr over } elseif {$x >= $y * (1 - $m)} { incr band } else continue
        if {$mode eq "on" && $m > 0} { set p [index_collection $P $i]; set_$ty [expr {$y * (1 - $m)}] $p; lappend ::QB_ECO_GUARDED [get_object_name $p] }
    }
    return "margin $m over $over band $band guarded [llength $::QB_ECO_GUARDED]"
}
# qb_eco_noise_guard on|off: the noise fix guard-band (header): bump height x 1 / (1 - QC_ECO_NOISE_MARGIN) on the design
# for the pass, 1.0 after it (r92 ss [M]: analysed pins 3274 / 3350 -> 3472 / 3553 under 1 / 0.98 -> 3274 / 3350).  The
# record has the violators under the guard (on: once set, the design before the fix; off: before the reset, the fixed
# design) = the sign-off violators + the pins in the fix band [immunity x (1 - margin), immunity], by PrimeTime's own
# noise model; the band = this count - noise_pre / noise_post.  (Not from the pins' slack: PrimeTime gives the
# si_noise_slack_* of every non-violating pin as the string POSITIVE, no number (R96 [M] r94 ss noise state: all 3138
# above_low / 3119 analysed below_high pins, the same in a single session); the band arithmetic on it was the r92 worker
# error "can't use non-numeric string as operand of *".)
proc qb_eco_noise_guard {mode} {
    set m $::env(QC_ECO_NOISE_MARGIN); set f [expr {1.0 / (1 - $m)}]
    if {$mode eq "on" && $m > 0} { set_noise_derate -height_factor $f }
    update_noise
    set r "margin $m bump height factor [format %.5f $f] under_guard [qb_eco_noise_count]"
    if {$mode eq "off" && $m > 0} { set_noise_derate -height_factor 1.0; update_noise }
    return $r
}
# qb_eco_noise_count (inside the noise state): violators at the current bump height factor, as the sign-off counts them
# (report_noise -all_violators; signoff/pt/common.tcl qb_pt_noise_viol)
proc qb_eco_noise_count {} {
    redirect -variable n { report_noise -all_violators -nosplit }
    return "noise [qb_pt_noise_viol $n]"
}
# qb_eco_noise_victims (inside the noise state): the violators of the same report, "victims {pin net ...}"
proc qb_eco_noise_victims {} {
    redirect -variable n { report_noise -all_violators -nosplit }
    set v {}
    foreach {- p net} [regexp -all -inline -line {^\s*(\S+)\s+\((\S+)\)\s+-?[0-9.]+\s+-?[0-9.]+\s+-?[0-9.]+\s*$} $n] { lappend v $p $net }
    return [list victims $v]
}
# Noise victims for the spacing rule (R116, PI decision; ICC2 flow/icc2/common.tcl qb_eco_noise_ndr).  [M] tau08 col/r102
# round 3: the one violator, ml_rcb U24/A2 on g_fin2_s2[16] (DFQD2 Q, 3 loads, 273 um, 265 um on M6), unfixable I Q: PT
# does not size a flop (above) and its only buffer (BUFFD2 at Q, without physical constraints) left the bump at 0.40 V
# against 0.39 V immunity (0.41 V before).  The net is coupling-bound: 55.6 of 64.6 fF wire cap is coupling, 43 fF of it
# to two parallel M6 nets of another lane; PT what-if: coupling x 0.75 -> 0.35 V, x 0.5 -> 0.24 V (clear); DFQD4 0.28 V.
# qb_eco_ndr_nets <unfixable reasons file of the last noise pass> <end_noise_victims records>: the victim nets of the end
# state's violators whose pin that pass reports unfixable, de-duplicated over the corners (a violator the pass did not
# see, e.g. one from the timing repair after it, is the next round's PT's)
proc qb_eco_ndr_nets {uf recs} {
    set up {}
    if {[file exists $uf]} {
        foreach l [split [exec cat $uf] "\n"] { if {[regexp {^\s*(\S+)\s+[A-Z]( [A-Z])*\s*$} $l -> p]} { dict set up $p 1 } }
    }
    set nets {}
    foreach {c x} $recs { foreach {p n} [dict get $x victims] { if {[dict exists $up $p]} { lappend nets $n } } }
    return [lsort -unique $nets]
}
# qb_eco_noise_enter on|off: the block's noise-only analysis state, ::QB_PT_NOISE_STATE of its PrimeTime script ("<command>
# on" enters it, "<command> off" restores the timing state), then the timing and noise update every later count needs
# (R92 [M] col: after off the constraints are exact again, act_o transitions within 0.00018 ns)
proc qb_eco_noise_enter {mode} {
    if {![info exists ::QB_PT_NOISE_STATE]} { return "none" }
    set r [{*}$::QB_PT_NOISE_STATE $mode]; update_timing; update_noise
    return $r
}
# qb_eco_noise_state on|off (master): qb_eco_noise_enter everywhere, around every noise pass and noise count.  A
# scenario whose PrimeTime script sets no ::QB_PT_NOISE_STATE is an error (its noise passes would silently run in another
# state than the sign-off's).
proc qb_eco_noise_state {mode} {
    set r [qb_eco_all noise_state_$mode "qb_eco_noise_enter $mode"]
    if {[lsearch -exact $r none] >= 0} {
        error "QB_PT_ECO: no ::QB_PT_NOISE_STATE from $::env(QB_PT_SCRIPT) in a scenario (noise_state_$mode lines)"
    }
}
# physical data of the ECO (R81): the ICC2 design library QB_ECO_NLIB / block QB_ECO_BLOCK, required (no
# logic-only fallback), clock-network physical data on (-physical_enable_clock_data, PT Q-2019.12-SP2 set_eco_options
# man: "Without this option, ECO operations ignore physical data for the clock network").
# The kit's DCAP* / FILL* are not PT standard fillers: without -filler_cell_names every row site is occupied
# (R56: 0 fillers identified, fix_eco_timing -type hold then made 0 changes)
proc qb_eco_phys {corner} {
    foreach v {QB_ECO_NLIB QB_ECO_BLOCK} { if {![info exists ::env($v)]} { error "qb_eco_phys: $v not set (the ECO is physically aware only, R81)" } }
    set_eco_options -physical_icc2_lib $::env(QB_ECO_NLIB) -physical_icc2_blocks $::env(QB_ECO_BLOCK) -physical_enable_clock_data \
        -filler_cell_names [concat $::QC_PNR_DCAP $::QC_PNR_FILL] -log_file $::env(QC_PNR_OUT)/out/eco/phys_$corner.log
}
# violator pins of a report_constraint -max_transition / -max_capacitance report that are in the clock network (PT pin
# attribute is_clock_network): the post-route clock DRV of R81 decision 3, counted before any ECO (qb_eco_timing_count)
proc qb_eco_clk_viol {rpt} {
    set n 0
    foreach {- p} [regexp -all -inline -line {^\s*(\S+)\s+[-0-9.]+\s+[-0-9.]+\s+[-0-9.]+\s+\(VIOLATED} $rpt] {
        set q [get_pins -quiet $p]
        if {[sizeof_collection $q] && [get_attribute -quiet $q is_clock_network] eq "true"} { incr n }
    }
    return $n
}
# new-cell record (R90; common/eco_changes.tcl): each cell the change list <chg> creates, as this session has it after the
# ECO: {full_name ref_name loads}.  ICC2 checks the cells it builds against it (flow/icc2/common.tcl qb_eco_names): R90 [M]
# a buffer of the right name and lib cell may still drive other loads than PT timed.
proc qb_eco_cells_write {chg} {
    current_instance
    set f [open [qb_eco_cells_file $chg] w]
    if {[file exists $chg]} {
        foreach x [qb_eco_new_cells $chg] {
            lassign $x full ref
            foreach_in_collection c [get_cells -quiet $full] { puts $f [list [get_object_name $c] [get_attribute $c ref_name] [qb_eco_loads $c]] }
        }
    }
    close $f
}
if {[info exists ::qb_eco_corner]} {
    # DMSA scenario process: design setup of this corner, then back to the master
    qb_eco_setup $::qb_eco_corner
    qb_eco_phys $::qb_eco_corner
    return
}
if {![info exists ::env(QB_ECO_CORNERS)]} { error "QB_PT_ECO: QB_ECO_CORNERS not set (the sign-off ECO loop, common/block.sh eco)" }
source [file join [file dirname [file normalize [info script]]] .. .. common limits.tcl]   ;# (qb_limit in the master)
source [file join [file dirname [file normalize [info script]]] .. .. common eco_changes.tcl]   ;# (qb_eco_change_count)
set eco_report_unfixed_reason_max_endpoints 1000
set dir $::env(QC_PNR_OUT); set o $dir/out/eco; file mkdir $o
file delete -force $o/pt_eco.tcl $o/pt_eco_cells.txt $o/pt_eco_ndr.txt   ;# (R90: never a change list or record of an earlier round)
set corners $::env(QB_ECO_CORNERS)
set_host_options -num_processes [llength $corners] -max_cores $::env(QB_ECO_CORES)
set multi_scenario_working_directory $o/work
puts "QB_PT_WORKDIR [file normalize $o/work]"   ;# (common/env.sh qb_pt: the scenario logs of this session)
set multi_scenario_merged_error_log $o/merged_errors.log
foreach c $corners {
    set qb_eco_corner $c
    create_scenario -name $c -specific_variables {qb_eco_corner} -specific_data [file normalize [info script]]
}
unset qb_eco_corner
start_hosts
current_session $corners
set ::QB_ECO_SF [open $o/eco_summary.txt w]
# the round's summary, closed, into the log; the scenario processes ended
proc qb_eco_end {o} {
    close $::QB_ECO_SF; unset ::QB_ECO_SF
    puts [exec cat $o/eco_summary.txt]
    stop_hosts
    puts "QB_PT_ECO done"
    exit
}
# pre-fix state at the sign-off criterion: the timing counts in the timing state (before the first noise state: header),
# the pins inside the DRV fix band, then noise in the noise state
set before [qb_eco_all before qb_eco_timing_count]
set tot [qb_eco_sum $before {setup hold recovery removal max_tran max_cap}]
set other [qb_eco_all before_signoff qb_eco_signoff_count]
foreach ty {max_transition max_capacitance} { qb_eco_all before_$ty "qb_eco_guard $ty scan" }
qb_eco_noise_state on
set nb [qb_eco_all before qb_eco_noise_count]
incr tot [qb_eco_sum $nb noise]
lappend other {*}[qb_eco_all before_signoff_noise qb_eco_signoff_noise_count]
qb_eco_noise_state off
# the sign-off's other gates (R103; before, prefix_total 0 was "converged" whatever they said, and the post step failed
# on them later): act_noise violators are noise the noise passes fix (PT man set_noise_parameters: both analysis types
# catch all noise violations), so they count in prefix_total; every other one is a check no ECO pass fixes (pulse width
# / period, annotation, coverage, undriven noise drivers, unanalysed act pins): any non-zero one stops the loop
set unfix {}
# (R114) a noise report qb_pt_noise_viol could not read (-1) is no count: unfixable, never summed into a smaller total
foreach {c x} $nb { if {[dict get $x noise] < 0} { incr tot [expr {-[dict get $x noise]}]; lappend unfix "$c:noise_unparsed" } }
foreach {c x} $other {
    dict for {k v} $x { if {$k eq "act_noise"} { incr tot $v } elseif {$v != 0} { lappend unfix "$c:$k=$v" } }
}
qb_eco_note "prefix_total $tot (setup + hold + recovery + removal + max_tran + max_cap + noise + act_noise violators of [llength $corners] corners before any fix, zero margin)"
qb_eco_note "prefix_tns [format %.4f [qb_eco_sum $before {setup_tns hold_tns}]] (setup + hold total negative slack of [llength $corners] corners before any fix, zero margin, ns)"
qb_eco_note "prefix_unfixable [llength $unfix] (non-zero sign-off counts no ECO pass fixes: [expr {[llength $unfix] ? [lrange $unfix 0 19] : "none"}])"
if {[llength $unfix]} {
    qb_eco_note "eco none: FAIL [llength $unfix] corner:check counts the sign-off fails and the ECO cannot fix (before_signoff* lines); no change list"
    qb_eco_end $o
}
set chk [expr {[info exists ::env(QB_ECO_CHECK)] && $::env(QB_ECO_CHECK)}]
if {$tot == 0 || $chk} {
    qb_eco_note "eco none: [expr {$tot == 0 ? "converged (pre-fix state clean in every corner)" : "check only (QB_ECO_CHECK)"}]"
    qb_eco_end $o
}
# buffer list of the scenario processes (the master has no libraries; every scenario has the same dont_use list)
current_scenario [lindex $corners 0]
redirect -variable r { remote_execute -verbose { puts "QB_ECO_BUFS [qb_eco_buffers]"; puts "QB_ECO_CBUFS [qb_eco_clock_buffers]" } }
current_scenario -all
if {![regexp {QB_ECO_BUFS (BUFF[^\n]*)} $r -> bufs]} { error "QB_PT_ECO: no ECO buffer list from [lindex $corners 0]" }
if {![regexp {QB_ECO_CBUFS (CK[^\n]*)} $r -> cbufs]} { error "QB_PT_ECO: no clock ECO buffer list from [lindex $corners 0]" }
qb_eco_note "physical_mode $::QB_ECO_PMODE (every pass, clock network with physical clock data); buffers $bufs; clock network buffers $cbufs"
qb_eco_drc $o/ $bufs $cbufs
qb_eco_all drc qb_eco_timing_count
# hold (R84): the ONE hold-cell list of ICC2 and this ECO (common/lib_cells.tcl qb_hold_cells: BUFFD<n> + the delay cells
# DEL<n>); the hold-only cells (site.tcl QC_HOLD_ONLY) are dont_use in every scenario outside the hold passes, so DRV /
# setup / noise never use them
current_scenario [lindex $corners 0]
redirect -variable r { remote_execute -verbose { puts "QB_ECO_HBUFS [qb_hold_cells]" } }
current_scenario -all
if {![regexp {QB_ECO_HBUFS (BUFF[^\n]*)} $r -> hbufs]} { error "QB_PT_ECO: no hold cell list from [lindex $corners 0]" }
# guard-band (header, 3.): the options only for a positive margin, so 0 is the former command (man: explicit zero
# margins "may not match" the default)
set hm $::env(QC_ECO_HOLD_MARGIN)
set hopt [expr {$hm > 0 ? [list -hold_margin $hm -slack_lesser_than $hm] : {}}]
qb_eco_note "hold cells $hbufs; hold margin $hm ns ($hopt)"
# setup fix margin (header, 2.; R108): the same form as the hold margin
set sm [qb_limit QC_ECO_SETUP_MARGIN]
set sopt [expr {$sm > 0 ? [list -setup_margin $sm -slack_lesser_than $sm] : {}}]
qb_eco_note "setup margin $sm ns ($sopt)"
# qb_eco_timing_fix <tag prefix>: setup to its fix margin (R67: residual setup violators of the sign-off timing; the
# column's act feedthroughs are dont_touch, R68), then hold to its guard-band, in the timing state; one state record
# after each; returns the records of the last (qb_eco_all)
proc qb_eco_timing_fix {px} {
    global o bufs hbufs hopt sopt
    fix_eco_timing -type setup -methods {size_cell insert_buffer} -buffer_list $bufs -physical_mode $::QB_ECO_PMODE {*}$sopt \
        -verbose -unfixable_reasons_prefix $o/${px}setup_unfixable -unfixable_reasons_format text
    qb_eco_all ${px}setup qb_eco_timing_count
    remote_execute { foreach p [qb_hold_only] { set c [get_lib_cells -quiet */$p]; if {[sizeof_collection $c]} { set_dont_use $c false } } }
    fix_eco_timing -type hold -methods {size_cell insert_buffer} -buffer_list $hbufs -physical_mode $::QB_ECO_PMODE {*}$hopt \
        -verbose -unfixable_reasons_prefix $o/${px}hold_unfixable -unfixable_reasons_format text
    remote_execute { foreach p [qb_hold_only] { set c [get_lib_cells -quiet */$p]; if {[sizeof_collection $c]} { set_dont_use $c true } } }
    return [qb_eco_all ${px}hold qb_eco_timing_count]
}
qb_eco_timing_fix ""
# noise after hold (R85, PI decision 4): fix_eco_timing -type hold keeps setup and max_transition / max_capacitance but not
# crosstalk noise.  [M] r84 eco_summary: ml_rcb noise 0 after the DRV and setup passes, 1 after the hold pass, which is
# the one post-ECO noise violator (b2[21], ml_rcb).  So a noise pass runs on the hold-fixed design, in the noise state
# without timing margins, and setup / hold are repaired after it in the timing state (header, 4. / 5.)
qb_eco_drc $o/post_hold_ $bufs {} noise
set end [qb_eco_timing_fix post_noise_]
qb_eco_noise_state on
set en [qb_eco_all end_noise qb_eco_noise_count]
set es [qb_eco_all end_signoff_noise qb_eco_signoff_noise_count]
set ev [qb_eco_all end_noise_victims qb_eco_noise_victims]
qb_eco_noise_state off
current_scenario [lindex $corners 0]
remote_execute "write_changes -format icc2tcl -output $o/pt_eco.tcl"
remote_execute "qb_eco_cells_write $o/pt_eco.tcl"
current_scenario -all
# write_changes writes no file when the round made no change (R64 [M]: round 2 at its fixed point); the change list is
# then empty, so flow/icc2/eco.tcl applies nothing
if {![file exists $o/pt_eco.tcl]} { set f [open $o/pt_eco.tcl w]; puts $f "# no ECO changes"; close $f }
set t [exec cat $o/pt_eco.tcl]
qb_eco_note "eco size_cell [regexp -all -line {^\s*size_cell} $t] insert_buffer [regexp -all -line {^\s*(insert_buffer|add_buffer\S*)} $t] lines [llength [split $t "\n"]]"
qb_eco_note "eco_changes [qb_eco_change_count $o/pt_eco.tcl] (change commands of pt_eco.tcl: its command lines but current_instance)"
# the end state at the sign-off criterion as prefix_total counts it (R116: the record of a round PrimeTime cannot fix)
set res {}
foreach {recs keys} [list $end {setup hold recovery removal max_tran max_cap} $en noise $es act_noise] {
    # (act_noise: a block hook's count, the column's; a block without it has none)
    foreach {c x} $recs { foreach k $keys { if {[dict exists $x $k] && [dict get $x $k] != 0} { lappend res "$c:$k=[dict get $x $k]" } } }
}
set ndr [qb_eco_ndr_nets $o/post_hold_drc_noise.txt $ev]
set f [open $o/pt_eco_ndr.txt w]; foreach n $ndr { puts $f $n }; close $f
qb_eco_note "eco_ndr_nets [llength $ndr] (pt_eco_ndr.txt: victim nets of the end state's noise violators the last noise pass left unfixable, for the spacing rule: [lrange $ndr 0 9])"
qb_eco_note "eco_residual [expr {[llength $res] ? $res : "none"}] (non-zero corner:check counts of prefix_total's checks after the change list, PrimeTime's prediction)"
qb_eco_end $o
