# R24 (results/r24.md): standalone post-CTS repair session on a copy of a run dir (run24.sh or):
# load db/[QB24_DB cts].odb (+ .sdc), then impl/pnr/slice_post_cts.tcl with QB_PC_HOOK (pc24.tcl) -> db/cts_rt.odb
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::T0 [clock seconds]
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 16]
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env QB24_DB cts]
source $::QB_DIR/slice_post_cts.tcl
qc_log "r24: pc done [expr {[clock seconds] - $::T0}] s"
exit
