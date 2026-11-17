# PRE_ROUTE_TCL of impl/r13/act.cfg: S1 cell padding again (DPL state is not in the checkpoint) + impl/r9a/post_cts.tcl.
source $::QB13_DIR/pad.tcl
source [file normalize $::QB13_DIR/../r9a/post_cts.tcl]
# QB13_STOP_RT 1: end the run after the post-CTS repair checkpoint db/cts_rt.odb (the route then runs as impl/r9a/run.sh rt with
# route_rt.tcl: the flow's own GRT with 50 iterations stalled on this block, r9a_f2r)
if {[qb_env QB13_STOP_RT 0]} { qc_log "r13 stop after post-CTS repair (db/cts_rt.odb)"; exit 0 }
