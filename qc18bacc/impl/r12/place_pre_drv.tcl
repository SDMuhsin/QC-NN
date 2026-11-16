# R12 DRV-limit variant (results/r12.md): PRE_PLACE_TCL override (QC_PNR_SET PRE_PLACE_TCL <this>) = impl/r10b/place_pre.tcl
# with the column-block P&R DRV limits: max transition QB_MAXTRAN (set 0.30 in the env; read by impl/r5b/pre_place.tcl)
# and max fanout QB12_MAXFO [32] instead of the hub SDC's 16.
source $::QB_R10B/place_pre.tcl
set_max_fanout [qb_env QB12_MAXFO 32] [current_design]
qc_log "r12: max_fanout [qb_env QB12_MAXFO 32], max_transition [qb_env QB_MAXTRAN 0.4]"
