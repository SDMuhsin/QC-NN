# PRE_ROUTE_TCL of impl/r9a/act.cfg: impl/pnr/slice_post_cts.tcl (post-CTS setup / hold repair, IO shift QB_IO_LAT) with
# extra repair_timing options QB9_RT_ARGS (e.g. {-verbose -skip_gate_cloning}).
if {[info commands qb9_rt_orig] eq ""} {
    rename repair_timing qb9_rt_orig
    proc repair_timing {args} { qb9_rt_orig {*}$args {*}[qb_env QB9_RT_ARGS {}] }
}
source $::QB_DIR/slice_post_cts.tcl
