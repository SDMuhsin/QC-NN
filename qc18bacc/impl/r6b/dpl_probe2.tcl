# impl/r6b: detailed-placement probe 2: db/pdn.odb + the legalised group placements (grp_<g>_L.pos), no DRV repair,
# then detailed_placement (QB_DPL_ARGS): is the chip-level dpl slow on an already legal placement?
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/pdn.odb
set ::env(QB_SNAP) 0; set ::env(QB_MAXTRAN) ""; set ::env(QB_STOP_DPL) 0; set ::env(QB_SPREAD) 0; set ::env(QB_POS_TAG) _L
source $::QB_R6B/place.tcl
proc qc_summary {l} { puts $l }
qb6_import
qb6_status PLACED
set t1 [clock seconds]
detailed_placement {*}[qb_env QB_DPL_ARGS {-max_displacement {1000 1000}}]
puts [format "DPL_PROBE2 dpl_s %d" [expr {[clock seconds] - $t1}]]
exit
