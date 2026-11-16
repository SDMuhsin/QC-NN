# impl/r7b QB7_BLKLAT [1] (place.tcl / cts_pre.tcl): remove the R5b DC-hook set_clock_latency -0.90 on the 8 column-block
# clk pins (in the P&R SDC since impl/hard/sdc_pnr.tcl copies the DC SDC; carried in db/<step>.sdc).  The block's clock
# insertion (0.96 ns tt) is inside the ETM arcs (setup act ~ -0.84, hold ~ +0.86 ns), so the clk pin must take the
# real top-tree arrival: ideal 0 before CTS (as the top flops), propagated after CTS.  With the latency OpenSTA kept
# the pins at an ideal -0.90 + 1.65 = 0.75 ns capture even after CTS (R6c).  Saved into db/place.sdc onwards.
if {[qb_env QB7_BLKLAT 1]} {
    set _bp [get_pins -quiet u_top/u_core/u_arr/g_c_*__u_col/clk]
    if {[llength $_bp]} { unset_clock_latency $_bp }
    qc_log "r7b: clock latency removed on [llength $_bp] block clk pins (block insertion via the ETM arcs + propagated clk pin)"
}
