# PRE_ROUTE_TCL of blocks/hub/hub.cfg (results/r21.md, r32.md, r34.md); one file for impl/r34/route_pre -> r21/route_pre:
#   1. count of the non-CK cells driving clock nets (R33 defect 3 check)
#   2. (R32) the IO-budget shift L is measured on this run's own post-CTS db (= db/cts.odb, placement parasitics,
#      propagated clock): p50 of the rise arrival at every register / macro clock pin.  It replaces QB_IO_LAT for the
#      post-CTS repair in this process and is written to <run>/r34_L.txt (blocks/hub/run.sh exports it to the later
#      steps: PT, ETMs)
#   3. route/postcts_grt.tcl: post-CTS setup / hold repair (repair/post_cts.tcl with the hub sequence
#      repair/hub_post_cts.tcl, QB_PC_HOOK) with the hub IO budget shifted by L, global_route -allow_congestion
#   4. the per-layer GRT adjustment QB15_GADJ_L after the flow's uniform P(GR_ADJUST) call
#   5. checkpoint db/cts_rt.odb before GRT (route input, for GRT-only reruns)
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
set_propagated_clock [all_clocks]
estimate_parasitics -placement
set _a {}
foreach p [all_registers -clock_pins] {
    set v ""
    foreach pr {arrival_max_rise max_rise_arrival} { if {![catch {get_property $p $pr} x] && $x ne ""} { set v $x; break } }
    if {$v eq "" || $v eq "INF" || $v eq "-INF"} continue
    if {$v < 1e-6} { set v [expr {$v * 1e9}] }
    lappend _a $v
}
set _a [lsort -real $_a]; set _n [llength $_a]
if {$_n > 100} {
    set _L [format %.3f [lindex $_a [expr {$_n / 2}]]]
    set ::env(QB_IO_LAT) $_L
    set _f [open $::OUT/r34_L.txt w]; puts $_f $_L; close $_f
    qc_log [format "r34: QB_IO_LAT measured %s (p50 of %d clock pins; p10 %.3f p90 %.3f min %.3f max %.3f)" $_L $_n \
        [lindex $_a [expr {$_n / 10}]] [lindex $_a [expr {9 * $_n / 10}]] [lindex $_a 0] [lindex $_a end]]
} else {
    qc_log "r34: QB_IO_LAT not measured ($_n clock pins), keeping [qb_env QB_IO_LAT 0.85]"
}
# post-CTS repair: the hub sequence (repair/hub_post_cts.tcl), setup repair of 10 % of the violating endpoints per pass
set ::env(QB_PC_HOOK) $::QBF/repair/hub_post_cts.tcl
set ::env(QB_TNS) 10
source $::QBF/route/postcts_grt.tcl
if {[qb_env QB15_GADJ_L ""] ne "" && [info commands qb21_gadj_orig] eq ""} {
    rename set_global_routing_layer_adjustment qb21_gadj_orig
    proc set_global_routing_layer_adjustment {layers adj} {
        qb21_gadj_orig $layers $adj
        qc_log "r21: gadj $layers $adj"
        foreach {l a} $::env(QB15_GADJ_L) { qb21_gadj_orig $l $a; qc_log "r21: gadj $l $a (QB15_GADJ_L)" }
    }
}
qc_save cts_rt
