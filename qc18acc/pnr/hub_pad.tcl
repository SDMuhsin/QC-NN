# PRE_PLACE_TCL of QC18-ACC with hub padding (qa3c.cfg, results/pnr_v3.md section 11): rows_fix.tcl, then extra
# placement padding of P(QA_HUB_PAD) sites left and right on the cells of the act-buffer / xbar / head hub (instance
# names matching P(QA_HUB_RE)), the blocks between the 48 act-macro read ports and the 64 PEs.  In qa3_t5b their
# global placement reached 95-100 % cell utilisation over ~200 x 500 um, where detailed route left 61 % of its 70 584
# markers (M2 / M3 shorts) while global route reported no overflow.
# set_placement_padding acts in detailed placement only (global placement ignores instance padding) and is not stored
# in the odb: hub_post_cts.tcl sets it again for the route step's legalisations, hub_post_grt.tcl clears it before
# the fillers (filler_placement ignores padding, check_placement does not: DPL-0033 overlap errors otherwise).
proc qa_hub_pad {pad} {
    set re [p QA_HUB_RE {^(u_xbar|u_act|u_head)/}]
    set insts {}
    foreach i [[ord::get_db_block] getInsts] {
        if {![[$i getMaster] isBlock] && [regexp $re [$i getName]]} { lappend insts [$i getName] }
    }
    set_placement_padding -instances [get_cells $insts] -left $pad -right $pad
    qc_log "hub_pad: [llength $insts] instances matching $re padded by $pad sites left / right"
}
if {![info exists ::qa_hub_lib_only]} {
    source [file normalize $::env(QC_FLOW)/../../qc18acc/pnr]/rows_fix.tcl
    qa_hub_pad [p QA_HUB_PAD]
}
