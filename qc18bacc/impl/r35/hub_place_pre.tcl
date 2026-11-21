# R35 opt-in PRE_PLACE_TCL of the hub (impl/r22/run.sh QB22_PRE_PLACE; results/r35a.md bugs 1 + 4): a buffer at every
# hub IO port before placement, so the abutted column -> hub inputs see one small buffer pin (was up to 333 fF) and the
# hub outputs (1 088 t2 pins on 3-mm top trunks) have a strong driver.  impl/r21/place_pre.tcl first (its remove_buffers
# would delete the port buffers), then buffer_ports, then global placement as usual.
#   QB35_INBUF [BUFFD2], QB35_OUTBUF [BUFFD8]
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r21/place_pre.tcl]
set _t [clock seconds]; set _n0 [llength [[ord::get_db_block] getInsts]]
buffer_ports -inputs -buffer_cell [qb_env QB35_INBUF BUFFD2]
set _n1 [llength [[ord::get_db_block] getInsts]]
buffer_ports -outputs -buffer_cell [qb_env QB35_OUTBUF BUFFD8]
set _n2 [llength [[ord::get_db_block] getInsts]]
qc_log "r35 hub port buffers: inputs [expr {$_n1 - $_n0}] outputs [expr {$_n2 - $_n1}] ([expr {[clock seconds] - $_t}] s)"
