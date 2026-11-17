# PRE_ROUTE_TCL of impl/r16/act.cfg: re-spread of the CTS checkpoint (respread.tcl), then impl/r13/post_cts.tcl
# (S1 DPL padding, r9a / slice post-CTS setup + hold repair, db/cts_rt.odb, stop with QB13_STOP_RT).
source $::QB16_DIR/respread.tcl
source $::QB13_DIR/post_cts.tcl
