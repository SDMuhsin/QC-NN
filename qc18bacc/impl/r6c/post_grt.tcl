# POST_GRT_TCL of impl/r6c/chip.cfg with QB_GRT_STOP 1: checkpoint db/grt.odb (+ route.guide from global_route) and exit,
# so detailed routing runs in a fresh process (run.sh dr -> dr.tcl).  r6c_gt: one process GRT + DR was OOM-killed at
# DR track assignment (RSS 31.2 GB, VM 47.8 GB on a 30-GB host): the global router's ~25-30 GB stay allocated.
qc_save grt
qc_log "r6c: stop after global route (QB_GRT_STOP)"
exit
