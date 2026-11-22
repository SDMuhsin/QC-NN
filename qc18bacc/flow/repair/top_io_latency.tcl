# Top IO latency (results/r43.md, defect 6), OpenROAD side: the chip IO delays are shifted by the top-register
# clock latency L (inputs 0.2 P + L, outputs 0.2 P - L).  L was a hand-copied QB36_TOPL (7.7 = a clk14 falling-edge
# number, see cts/top_clk_measure.tcl).  q43_autol <tag>: L = median of the clk14 top-flop group medians (rising
# edge) at the current parasitics; sets ::env(QB_IO_LAT) (read by repair/post_cts.tcl)
# and re-applies the IO delays now.  OR times tt only; PT measures each corner itself (signoff/pt/top_chip.tcl).
proc q43_autol {tag} {
    q14_measure
    set l {}
    foreach k [array names ::Q14_EFF] { if {![regexp {^(col\d|hub|act)$} $k]} { lappend l $::Q14_EFF($k) } }
    if {![llength $l]} { qc_log "r43 autol $tag: no top-flop groups"; return }
    set l [lsort -real $l]; set L [lindex $l [expr {[llength $l] / 2}]]
    set ::env(QB_IO_LAT) [format %.3f $L]; set ::env(QB35_TOPL) $::env(QB_IO_LAT)
    set per [get_property [get_clocks qb_clk] period]
    set ins {}; set outs {}
    foreach b [[ord::get_db_block] getBTerms] {
        set n [$b getName]
        if {$n in {clk rst_n} || [$b getSigType] ne "SIGNAL"} { continue }
        if {[$b getIoType] eq "INPUT"} { lappend ins $n } elseif {[$b getIoType] eq "OUTPUT"} { lappend outs $n }
    }
    set_input_delay [expr {0.2 * $per + $L}] -clock qb_clk [get_ports $ins]
    set_output_delay [expr {0.2 * $per - $L}] -clock qb_clk [get_ports $outs]
    qc_summary [format "r43 autol %s L %.3f ns (median of %d top-flop group medians, rising edge)" $tag $L [llength $l]]
}
