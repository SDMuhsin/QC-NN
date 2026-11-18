# R25 (results/r25.md): short marker DR = impl/r8/dr.tcl (imported, not copied) stopped right after detailed_route:
# no save, no fillers, no finish / SPEF.  Iterations / extra args through hub.cfg QB_DR_ITER / QB_DR_ARGS (run.sh dr).
rename detailed_route qb25_drt
proc detailed_route {args} {
    set t [clock seconds]; qb25_drt {*}$args
    qc_log "r25 dr: detailed_route [expr {[clock seconds] - $t}] s, stop without save"; exit
}
source $::env(QC_FLOW)/../../qc18bacc/impl/r8/dr.tcl
