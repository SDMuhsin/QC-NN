# Per-layer GRT capacity adjustment (R15 / R30 fix): the pairs "<layer range> <adj> ..." of QB15_GADJ_L are applied after
# every uniform set_global_routing_layer_adjustment call (the flow's route step makes one with P(GR_ADJUST)).
# Sourced by a PRE_ROUTE_TCL hook; idempotent.
if {[qb_env QB15_GADJ_L ""] ne "" && [info commands qb_gadj_orig] eq ""} {
    rename set_global_routing_layer_adjustment qb_gadj_orig
    proc set_global_routing_layer_adjustment {layers adj} {
        qb_gadj_orig $layers $adj
        foreach {l a} $::env(QB15_GADJ_L) { qb_gadj_orig $l $a; qc_log "gadj $l $a (QB15_GADJ_L)" }
    }
}
