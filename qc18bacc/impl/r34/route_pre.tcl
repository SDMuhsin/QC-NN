# R34 PRE_ROUTE_TCL (impl/r34/preset.env; results/r34.md): opt-in QB34_LAT 1 (R32): the IO-budget shift L (QB_IO_LAT)
# is measured on this run's own post-CTS db (= db/cts.odb, placement parasitics, propagated clock): p50 of the rise
# arrival at every register / macro clock pin, as impl/r21/clk_lat.tcl.  It replaces the constant for the post-CTS
# repair in this process and is written to <run>/r34_L.txt (impl/r34/run34.sh exports it to the later steps: PT, ETMs).
# Also counts the non-CK cells driving clock nets (R33 defect 3 check).  Then impl/r21/route_pre.tcl.
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
if {[qb_env QB34_LAT 0]} {
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
}
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r21/route_pre.tcl]
# opt-in QB34_ANT_EARLY 1 (results/r34.md sec. 5): the antenna netlist / PDN edits of the dio step (pdn29 strap trim,
# buf31 macro-input BUFFD2 + their DPL, which moved cells up to 227 um after the post-GRT timing repair) are made here,
# after the post-CTS repair and the cts_rt checkpoint, before the global route; the GRT and the post-GRT repair then
# see them.  The dio step then only adds diodes (preset: R31_PDN "").  ('s' is the flow's step variable: kept.)
if {[qb_env QB34_ANT_EARLY 0]} {
    set _s34 $s; set _t34 [clock seconds]
    source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r29/pdn29.tcl]
    source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r31/buf31.tcl]
    set s $_s34
    estimate_parasitics -placement
    qc_log "r34: antenna edits before GRT (pdn29 + buf31) [expr {[clock seconds] - $_t34}] s"
}
