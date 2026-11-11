# Run after global placement (xbar_place.tcl wraps global_placement) and as PRE_CTS_TCL of qa4b.cfg (no-op then):
# the crossbar stage registers placed FIRM by xbar_place.tcl become PLACED again, so that the DRV / timing repair
# and the legalisations may resize / move them like any other cell.
set n 0
foreach i [[ord::get_db_block] getInsts] {
    if {![[$i getMaster] isBlock] && [$i getPlacementStatus] eq "FIRM" && [regexp {^(u_act/ar_rdata_reg|u_xbar/(sa|win)_reg)} [$i getName]]} {
        $i setPlacementStatus PLACED; incr n
    }
}
qc_log "xbar_unfix: $n crossbar registers FIRM -> PLACED"
# P(QA_MACRO_ICG) <cell> (qa4c.cfg: CKLNQD16): macro clock gates resized and moved next to their macros (macro_icg.tcl)
if {[info exists ::qa_xbar_cts] == 0 && [p QA_MACRO_ICG ""] ne "" && [info level] == 0} {
    set ::qa_xbar_cts 1
    source [file normalize $::env(QC_FLOW)/../../qc18acc/pnr]/macro_icg.tcl
}
