# Max-transition / max-capacitance repair (R45 bug 3, results/r45.md): violators-only repair_design (the flow's
# qc_repair_drv: every other signal net dont_touch, so DC's sizing is kept) run after CTS, after every hold insertion and
# after GRT (repair/post_cts.tcl, route/*_post_grt.tcl, route/act_route.tcl, repair/hold_eco.tcl, repair/top_hold.tcl).
# OpenROAD times tt only; the sign-off checks tt and ss (PT, max transition min(0.5, 0.1 P) and the library limits).  So
# the P&R max transition is QB_DRV_SLEW [0.33 ns] (ss slew ~1.45 x tt [E], 1.45 x 0.33 < 0.5) and repair_design runs with
# -cap_margin QB_DRV_CAPM [15] %.  Callers legalise afterwards (detailed_placement) unless stated otherwise.
proc qb_drv_count {} {
    return [list [sta::max_slew_violation_count] [sta::max_capacitance_violation_count] [sta::max_fanout_violation_count]]
}
# qb_drv <tag>: repair the DRV nets at the current parasitics; returns the number of nets that had violations
proc qb_drv {tag} {
    set_max_transition [qb_env QB_DRV_SLEW 0.33] [current_design]
    lassign [qb_drv_count] s c f
    set n [expr {$s + $c + $f}]
    if {$n > 0} { qc_repair_drv -cap_margin [qb_env QB_DRV_CAPM 15] }
    lassign [qb_drv_count] s2 c2 f2
    qc_summary "drv $tag max_slew [qb_env QB_DRV_SLEW 0.33] slew/cap/fanout violators $s/$c/$f -> $s2/$c2/$f2"
    return $n
}
# qb_drv_grt <tag> <global_route args>: the same at global-route parasitics, legalised, then a full global route with the
# caller's own GRT arguments and GRT parasitics re-estimated.  (Not an incremental GRT: r48_col, 86 buffers + 1 417
# resizes + legalisation, global_route -end_incremental stopped with GRT-0232 where the full route had converged.)
proc qb_drv_grt {tag args} {
    set n [qb_drv $tag]
    if {$n == 0} return
    detailed_placement {*}[p DPL_ARGS]; check_placement
    set t [clock seconds]
    global_route {*}$args
    estimate_parasitics -global_routing
    lassign [qb_drv_count] s c f
    qc_summary "drv $tag after legalisation + full GRT ([expr {[clock seconds] - $t}] s) slew/cap/fanout violators $s/$c/$f"
}
