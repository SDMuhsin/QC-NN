# PRE_ROUTE_TCL of blocks/hub/hub.cfg: post-CTS setup / hold repair (repair/post_cts.tcl, QB_POSTCTS 1) with the
# hub IO budget shifted by QB_IO_LAT, then the flow's global_route with -allow_congestion (QB_GRT_ALLOW 1: overflow is
# reported, not fatal).
if {[qb_env QB_POSTCTS 1]} { source [file normalize $::env(QC_FLOW)/../../qc18bacc/flow/repair/post_cts.tcl] }
if {[qb_env QB_GRT_ALLOW 1] && [info commands qb9_grt_orig] eq ""} {
    rename global_route qb9_grt_orig
    proc global_route {args} {
        lappend args -allow_congestion
        qc_log "r9b: global_route $args"
        set t [clock seconds]; qb9_grt_orig {*}$args; qc_log "r9b: global_route [expr {[clock seconds] - $t}] s"
    }
}
