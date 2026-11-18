# R21 PRE_ROUTE_TCL: impl/r9b/route_pre.tcl (post-CTS setup / hold repair with the IO budget shifted by QB_IO_LAT,
# global_route -allow_congestion) plus the R15 per-layer GRT adjustment QB15_GADJ_L (e.g. "M5-M9 0.10"), applied
# after the flow's uniform P(GR_ADJUST) call (same wrapper as impl/r15/grt15.tcl; unset = uniform).
source $::QB_R9B/route_pre.tcl
if {[qb_env QB15_GADJ_L ""] ne "" && [info commands qb21_gadj_orig] eq ""} {
    rename set_global_routing_layer_adjustment qb21_gadj_orig
    proc set_global_routing_layer_adjustment {layers adj} {
        qb21_gadj_orig $layers $adj
        qc_log "r21: gadj $layers $adj"
        foreach {l a} $::env(QB15_GADJ_L) { qb21_gadj_orig $l $a; qc_log "r21: gadj $l $a (QB15_GADJ_L)" }
    }
}
# checkpoint before GRT (route input, for GRT-only reruns / the M5 control on the same netlist + placement)
qc_save cts_rt
