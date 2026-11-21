# R37 opt-in QB37_HPOST_TCL of impl/r35/hold35.tcl (results/r37.md sec. 11), sourced right after its legalisation + global
# route + estimate (h35 after_legal_grt_est): up to QB37_HPOST_N [2] more rounds of
#   repair_timing -hold at global-route parasitics (margin QB37_HPOST_M [0.03]; outputs offset by the margin, as
#   actpre37 / QB37_OMIN, so only reg2reg / in2reg get the margin) -> detailed_placement -> global_route -> estimate,
# stopping when the hold check at margin 0 is clean.  Cause: the first repair runs on the routed SPEF, then legalising
# its buffers moves 12-26k cells and the re-route moves hold by -0.02 (1.9k buffers) to -0.21 ns (16k buffers); repairing
# at the post-legalisation global-route parasitics adds few cells, so the next legalisation hardly moves anything.
set _m [qc_env QB37_HPOST_M 0.03]
for {set _r 1} {$_r <= [qc_env QB37_HPOST_N 2]} {incr _r} {
    set _nv 0; catch { set _nv [sta::endpoint_violation_count min] }
    if {$_nv == 0} { puts "R37_HPOST round $_r: hold clean at margin 0"; break }
    set_output_delay -min [expr {-$::env(QB35_IOL) + $_m}] -clock qb_clk [all_outputs]
    set _n0 [llength [$blk getInsts]]
    if {[catch { repair_timing -hold -hold_margin $_m -max_buffer_percent [qc_env QB35_HOLD_PCT 20] -max_utilization [qc_env QB35_MAXU 95] } e]} { puts "R37_HPOST repair stopped: $e" }
    set_output_delay -min [expr {-$::env(QB35_IOL)}] -clock qb_clk [all_outputs]
    puts "R37_HPOST round $_r: [expr {[llength [$blk getInsts]] - $_n0}] hold buffers (margin $_m)"
    detailed_placement {*}[p DPL_ARGS]
    foreach n [$blk getNets] { if {[$n isSpecial]} continue; set w [$n getWire]; if {$w ne "NULL"} { odb::dbWire_destroy $w } }
    global_route -guide_file $::OUT/route_hold.guide -allow_congestion -congestion_iterations 10
    estimate_parasitics -global_routing
    h35 hpost_round_$_r
}
