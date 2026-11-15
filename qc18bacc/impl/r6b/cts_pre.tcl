# PRE_CTS_TCL of impl/r6b/chip.cfg: when the flow restarts at the cts step (QC_PNR_FROM=cts) with QB_SPREAD 2 +
# QB_SPREAD_ALL 1, load the place.tcl procedures so the CTS detailed placement is preceded by spread2 of the new clock
# buffers (r6b_c: the CTS detailed placement without it was still in diamond search after 6 min).
if {[qb_env QB_SPREAD_ALL 0] && [info commands qb6_spread2] eq ""} {
    set _s [qb_env QB_SNAP 0]; set ::env(QB_SNAP) 0
    source $::QB_R6B/place.tcl
    set ::env(QB_SNAP) $_s
    set ::QB6_FIRST_DONE 1
    qb6_record
    qc_log "r6b: cts_pre: spread2 before every detailed placement"
}
