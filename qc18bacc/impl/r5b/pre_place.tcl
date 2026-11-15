# PRE_PLACE_TCL of impl/r5b/chip.cfg (QB_RMBUF 1, default): remove the DC buffer trees before global placement (as the
# OpenROAD-flow-scripts floorplan step does), so that repair_design buffers the nets for the real placement.  DC
# topographical buffered for its own square die with the column blocks as 0.9-mm2 obstacles (results/r5b.md): kept,
# those trees made 406 k repair buffers in run r5b_t.
# QB_MAXTRAN (ns, default 0.4; empty: keep the SDC's): design max transition for the DRV repair instead of the P&R SDC's min(0.5, 0.1 P) (r5b_u: at 0.2 ns
# the repair of the top-level buses doubled the standard-cell area, 2.4 -> 5.2 mm2, utilisation > 100 %).
if {[qb_env QB_MAXTRAN 0.4] ne ""} { set_max_transition [qb_env QB_MAXTRAN 0.4] [current_design]; qc_log "pre_place: max_transition [qb_env QB_MAXTRAN 0.4]" }
if {[qb_env QB_RMBUF 1]} {
    set _n0 [llength [[ord::get_db_block] getInsts]]
    remove_buffers
    qc_log "pre_place: remove_buffers [expr {$_n0 - [llength [[ord::get_db_block] getInsts]]}] instances removed"
}
# QB_GPL_INCR 1 (default): impl/pnr/gpl_incr.tcl (incremental global placement + second DRV repair after the place
# step's DRV repair): without it the repair buffers on long wires (r5b_t: 406 k, many over the column blocks / macros)
# are legalised in place and detailed placement sat > 30 min in diamond search (stack: Opendp::diamondSearch).
if {[qb_env QB_GPL_INCR 1]} { source $::QB_DIR/gpl_incr.tcl }
