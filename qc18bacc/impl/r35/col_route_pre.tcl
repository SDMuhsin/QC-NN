# R35 PRE_ROUTE_TCL of impl/r35/col.cfg: the column's post-CTS step (impl/pnr/slice_post_cts.tcl, as slice.cfg) plus
# the per-layer GRT adjustment QB15_GADJ_L (R30 fix: M2-M3 0.6) applied after the flow's uniform GR_ADJUST call
# (same wrapper as impl/r21/route_pre.tcl).
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/pnr/slice_post_cts.tcl]
if {[qb_env QB15_GADJ_L ""] ne "" && [info commands qb35_gadj_orig] eq ""} {
    rename set_global_routing_layer_adjustment qb35_gadj_orig
    proc set_global_routing_layer_adjustment {layers adj} {
        qb35_gadj_orig $layers $adj
        foreach {l a} $::env(QB15_GADJ_L) { qb35_gadj_orig $l $a; qc_log "r35: gadj $l $a (QB15_GADJ_L)" }
    }
}
