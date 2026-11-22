# PRE_ROUTE_TCL of blocks/hub/hub.cfg (results/r21.md, r32.md, r34.md); one file for impl/r34/route_pre -> r21/route_pre:
#   1. count of the non-CK cells driving clock nets (R33 defect 3 check)
#   2. route/postcts_grt.tcl: post-CTS DRV / setup / hold repair (repair/post_cts.tcl with the hub sequence
#      repair/hub_post_cts.tcl, QB_PC_HOOK) with the hub IO budget shifted by the measured insertion delay L
#      (cts/clk_lat.tcl), global_route -allow_congestion
#   3. the per-layer GRT adjustment QB15_GADJ_L after the flow's uniform P(GR_ADJUST) call (route/gadj_layers.tcl)
#   4. checkpoint db/cts_rt.odb before GRT (route input, for GRT-only reruns)
proc qb34_ckcount {tag} {
    set nb 0
    foreach i [[ord::get_db_block] getInsts] {
        if {![regexp {^(BUFF|INV)} [[$i getMaster] getName]]} continue
        foreach it [$i getITerms] {
            if {[$it isOutputSignal] && [$it getNet] ne "NULL" && [[$it getNet] getSigType] eq "CLOCK"} { incr nb }
        }
    }
    qc_log "r34: $tag non-CK buffers / inverters driving clock nets: $nb"
}
qb34_ckcount cts
# post-CTS repair: the hub sequence (repair/hub_post_cts.tcl), setup repair of 10 % of the violating endpoints per pass
set ::env(QB_PC_HOOK) $::QBF/repair/hub_post_cts.tcl
set ::env(QB_TNS) 10
source $::QBF/route/postcts_grt.tcl
source $::QBF/route/gadj_layers.tcl
qc_save cts_rt
