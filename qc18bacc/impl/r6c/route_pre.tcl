# PRE_ROUTE_TCL of impl/r6c/chip.cfg: when the flow restarts at the route step, load the R6b / R6c spread procedures
# (QB_SPREAD_ALL 1: every post-CTS legalisation preceded by spread2 / spread3 of the new / resized cells), then the
# post-CTS timing repair impl/pnr/slice_post_cts.tcl.
if {[qb_env QB_SPREAD_ALL 0] && [info commands qb6_spread2] eq ""} { source $::QB_R6B/cts_pre.tcl }
if {[qb_env QB_SPREAD3 0] && [info commands qb6c_spread3] eq ""} { source $::QB_R6C/spread3.tcl }
source $::QB_R6C/est_rc.tcl
# QB_BLK_PROP 1: remove the R5b DC-hook clock latency (-0.90 ns, set_clock_latency on the column-block clk pins) so the
# block clk pins take the propagated arrival of the CTS tree.  With it, OpenSTA keeps those pins ideal (capture
# 'clock network delay (ideal)' 0.75 ns at 1.65 ns) while the top flops are propagated (3.3 ns at r6c_h CTS): every
# top -> block setup check is ~2.6 ns too pessimistic and every block -> top hold check as optimistic in reverse, and
# the post-CTS repair works on those false violations.  The block-internal insertion (0.96 ns tt) is inside the ETM
# arcs (PT sign-off uses the same ETMs with the propagated clock).
if {[qb_env QB_BLK_PROP 0]} {
    set _bp [get_pins -quiet u_top/u_core/u_arr/g_c_*__u_col/clk]
    if {[llength $_bp]} { unset_clock_latency $_bp }
    qc_log "r6c: clock latency removed on [llength $_bp] block clk pins (propagated)"
}
# QB_NOHOLD 1: repair_timing -hold is skipped (logged).  r6c_h pre-repair: 100 628 hold endpoints, worst -5.586 ns =
# column-block act inputs whose ETM hold arc is 5.9-8.2 ns (act feedthrough chain; same arcs setup -7.0 ns), so a
# top-level hold repair would add ~6 ns of delay cells on ~1e5 nets; hold is reported by PrimeTime at sign-off instead.
if {[qb_env QB_NOHOLD 0] && [info commands qb6c_rt_orig] eq ""} {
    rename repair_timing qb6c_rt_orig
    proc repair_timing {args} {
        if {"-hold" in $args} { qc_log "r6c: repair_timing $args skipped (QB_NOHOLD)"; return }
        qb6c_rt_orig {*}$args
    }
}
# QB_GRT_ALLOW 1: global_route of the flow's route step gets -allow_congestion (overflow reported, not fatal), and
# QB_GRT_CRIT <pct> adds -critical_nets_percentage <pct>
if {([qb_env QB_GRT_ALLOW 0] || [qb_env QB_GRT_CRIT ""] ne "") && [info commands qb6c_grt_orig] eq ""} {
    rename global_route qb6c_grt_orig
    proc global_route {args} {
        if {[qb_env QB_GRT_ALLOW 0]} { lappend args -allow_congestion }
        if {[qb_env QB_GRT_CRIT ""] ne ""} { lappend args -critical_nets_percentage [qb_env QB_GRT_CRIT ""] }
        qc_log "r6c: global_route $args"
        set t [clock seconds]; qb6c_grt_orig {*}$args; qc_log "r6c: global_route [expr {[clock seconds] - $t}] s"
    }
}
# QB_SKIP_RT 1: no post-CTS timing repair (impl/pnr/slice_post_cts.tcl not run): r6c_h / r6c_gt, the legalisation
# after repair_timing turned WNS -6.4 / -8.1 into -14.8 / -14.4 ns [OR est.] (resized cells displaced in full rows)
if {[qb_env QB_SKIP_RT 0]} { qc_log "r6c: post-CTS repair skipped (QB_SKIP_RT)"; write_db $::OUT/db/cts_rt.odb } else { source $::QB_DIR/slice_post_cts.tcl }
