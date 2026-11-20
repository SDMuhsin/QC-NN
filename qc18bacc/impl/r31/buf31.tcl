# R31 (results/r31.md): opt-in antenna fix by isolation, sourced by impl/r29/dio29.tcl through R29_PDN (after the db is
# loaded, before its global route).  Every macro (BLOCK) signal input pin on a net whose pin HPWL exceeds R31_BHPWL um
# [300] (clock pins and tie-driven nets skipped) gets its own buffer R31_BCELL [BUFFD2] placed just outside the macro
# edge nearest to the pin (DPL legalises): the long net then ends on the buffer input (gate 0.0546 um2 instead of the
# macro's 0.009), and the macro pin hangs on a short net.  Cause: the qb_p D pins fail the cut-layer partial ratio
# (VIA78 / VIA89 28.8 vs 20) whenever DR reaches them from M8 / M9, and a diode elsewhere on the net is not in their island.
set _blk [ord::get_db_block]; set _u [expr {double([$_blk getDefUnits])}]
set _bm [[ord::get_db] findMaster [qc_env R31_BCELL BUFFD2]]
set _thr [qc_env R31_BHPWL 300]; set _nb 0; set _cls {}
proc _hpwl {n} {
    set x0 1e18; set y0 1e18; set x1 -1e18; set y1 -1e18
    foreach t [$n getITerms] { set b [$t getBBox]; set x [$b xMin]; set y [$b yMin]
        set x0 [expr {min($x0,$x)}]; set y0 [expr {min($y0,$y)}]; set x1 [expr {max($x1,$x)}]; set y1 [expr {max($y1,$y)}] }
    foreach t [$n getBTerms] { foreach p [$t getBPins] { set b [$p getBBox]; set x [$b xMin]; set y [$b yMin]
        set x0 [expr {min($x0,$x)}]; set y0 [expr {min($y0,$y)}]; set x1 [expr {max($x1,$x)}]; set y1 [expr {max($y1,$y)}] } }
    expr {($x1 - $x0 + $y1 - $y0) / $::_u}
}
set _todo {}
foreach i [$_blk getInsts] {
    if {[[$i getMaster] getType] ne "BLOCK"} continue
    foreach it [$i getITerms] {
        if {![$it isInputSignal]} continue
        set mt [$it getMTerm]; if {[$mt getSigType] ne "SIGNAL" || [string match CLK* [$mt getName]]} continue
        set n [$it getNet]; if {$n eq "NULL" || [$n getSigType] ne "SIGNAL"} continue
        set tie 0; foreach t [$n getITerms] { if {[$t isOutputSignal] && [string match TIE* [[[$t getInst] getMaster] getName]]} { set tie 1 } }
        if {$tie || [_hpwl $n] <= $_thr} continue
        lappend _todo $it
    }
}
foreach it $_todo {
    set i [$it getInst]; set n [$it getNet]
    set b [$it getBBox]; set x [$b xMin]; set y [$b yMin]; set m [$i getBBox]
    set d [list [expr {$x - [$m xMin]}] [expr {[$m xMax] - $x}] [expr {$y - [$m yMin]}] [expr {[$m yMax] - $y}]]
    switch [lsearch $d [tcl::mathfunc::min {*}$d]] {
        0 { set x [expr {[$m xMin] - 6000}] } 1 { set x [expr {[$m xMax] + 2000}] }
        2 { set y [expr {[$m yMin] - 8000}] } 3 { set y [expr {[$m yMax] + 2000}] }
    }
    incr _nb
    set bi [odb::dbInst_create $_blk $_bm r31_mb_$_nb]; $bi setLocation $x $y; $bi setPlacementStatus PLACED
    set nn [odb::dbNet_create $_blk r31_mbn_$_nb]; $nn setSigType SIGNAL
    $it disconnect; $it connect $nn
    [$bi findITerm I] connect $n; [$bi findITerm Z] connect $nn
    dict incr _cls [[$i getMaster] getName]/[regsub {\[.*} [[$it getMTerm] getName] {}]
}
puts "R31_BUF macro-input buffers $_nb (HPWL > $_thr um, [$_bm getName]): $_cls"
if {$_nb} { detailed_placement {*}[qc_env R29_DPL_ARGS "-max_displacement 500"] }
