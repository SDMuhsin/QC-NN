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
#   qb_pt_spef <spef>         read_parasitics of the ICC2 SPEF with its coupling capacitances kept (SI)
#   qb_pt_lat <dir> <corner>  insertion delay L of this corner: p50 of the rise arrival at every register / macro clock pin
#                             (the definition the P&R uses, cts/clk_lat.tcl); "<p50> <min> <max>" written to
#                             <dir>/out/clk_lat_<corner>.txt, which the chip top reads (blocks/top/run.sh views)
#   qb_pt_ann                 SPEF annotation line "total N rc_network N coupled_network N not_annotated N" (totals row
#                             of report_annotated_parasitics; with coupling kept it has the Coupled network column, R64)
#   qb_pt_drv <fh>            sign-off DRV line: max-transition and max-capacitance violators (design + library limits)
#   qb_etm_inputs             ETM extraction context (R45 bug 2): no driving cell on any input, clk included
#                             (constraints.sdc / the hub SDC put a BUFFD4 on the data inputs and a CKBD8 on clk,
#                             extract_model then varied the driving cell's *input* slew: MEXT-81, and the R63 clock
#                             tables ignored the clk slew), so the ETM index is the port slew.  extract_model writes an
#                             input pin's max_transition = the context slew of its port (R64 [M] on r62: input transition
#                             0 -> 0 on every input, 0.2 -> 0.2; a port set_max_transition or the extract_model_*_
#                             transition_limit variables leave it at 0), so every input gets the design max_transition
#                             (min(0.5, 0.1 P), constraints.sdc) as its input transition, and the tables are
#                             characterised up to that limit (extract_model_{data,clock}_transition_limit, default 5 ns)
#   OCV derate late 1.05 / early 0.95 on cell + net delays (common/derate.tcl, the same as the ICC2 timer), applied when
#   sourced (after the caller's constraints)
set_app_var timing_crpr_threshold_ps 1
set_app_var si_enable_analysis true
source [file normalize [file dirname [info script]]/../../common/derate.tcl]
qb_derate
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
proc qb_pt_ann {} {
    redirect -variable ann { report_annotated_parasitics }
    if {![regexp {\n\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|} $ann -> tot rc cc na]} { return NA }
    return "total $tot rc_network $rc coupled_network $cc not_annotated $na"
}
proc qb_pt_drv {fh} {
    redirect -variable t { report_constraint -max_transition -all_violators -nosplit }
    redirect -variable c { report_constraint -max_capacitance -all_violators -nosplit }
    puts $fh "drv max_transition_violators [regexp -all -line {VIOLATED} $t] max_capacitance_violators [regexp -all -line {VIOLATED} $c] (design max_transition [get_attribute [current_design] max_transition])"
}
proc qb_pt_spef {spef} {
    read_parasitics -keep_capacitive_coupling -format spef $spef
}
proc qb_etm_inputs {} {
    set in [all_inputs]
    set mt [get_attribute [current_design] max_transition]
    remove_driving_cell $in
    set_input_transition $mt $in
    set_app_var extract_model_data_transition_limit $mt
    set_app_var extract_model_clock_transition_limit $mt
    puts "QB_ETM inputs: driving cells removed, input transition = table limit = max_transition $mt on [sizeof_collection $in] ports"
}
