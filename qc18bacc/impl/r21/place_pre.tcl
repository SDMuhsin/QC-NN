# R21 PRE_PLACE_TCL of the hub production run (impl/r21/run.sh): impl/r10b/place_pre.tcl unchanged (max transition
# QB_MAXTRAN [0.4], remove_buffers, incremental gpl, QB9_CHBLK, QB9_GPL2), plus an optional design max fanout
# QB21_MAXFO (unset: the SDC's 16) - the column / act blocks place with 32 (impl/r9a, r19, r20 QB9_MAXFO).
source $::QB_R10B/place_pre.tcl
if {[qb_env QB21_MAXFO ""] ne ""} {
    set_max_fanout [qb_env QB21_MAXFO 16] [current_design]
    qc_log "r21: max_fanout [qb_env QB21_MAXFO 16] max_transition [qb_env QB_MAXTRAN 0.4]"
}
