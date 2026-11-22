# PRE_PLACE_TCL of core.cfg: incremental global placement after the place step's DRV repair, then the DRV repair of
# the nets the move broke (the fix of qc18acc/results/pnr_v4.md section 2 mechanism 4, qc18acc/pnr/xbar_place.tcl
# P(QA_GPL_INCR), without its macro / blockage parts).  Without it the repair buffers (qbs: 28 k, qbc: 363 k on long
# IO / broadcast wires) are legalised in place and detailed placement sat > 15 min in diamond search.
# P(QB_GPL_INCR_DENS): density of the incremental pass (default PLACE_DENSITY + 0.06).
if {[info commands qb_drv_orig] eq ""} {
    rename qc_repair_drv qb_drv_orig
    proc qc_repair_drv {} {
        qb_drv_orig
        set dens [p QB_GPL_INCR_DENS [expr {[p PLACE_DENSITY] + 0.06}]]
        qc_log "gpl_incr: incremental global placement after the DRV repair, density $dens [qc_util]"
        global_placement -incremental -density $dens -pad_left [p PLACE_PAD] -pad_right [p PLACE_PAD] {*}[p GPL_ARGS]
        estimate_parasitics -placement
        qc_log "gpl_incr: DRV repair after the incremental pass"
        qb_drv_orig
    }
}
