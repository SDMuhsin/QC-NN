# R37 (results/r37.md): opt-in pre-repair hook of impl/r35/hold35.tcl (QB37_HPRE_TCL): a buffer QB37_IBCELL [BUFFD2] at every
# block signal INPUT port whose net HPWL exceeds QB37_IBHPWL um [300] (clock ports skipped), placed at the port pin pulled
# QB37_IBIN um [3] into the core (hold35's detailed_placement legalises).  The long wire then hangs on the buffer output,
# the port sees one buffer pin: the r35a bug-1 fix of the hub applied to the act, where tt ETM extraction produced
# absurd setup / hold tables (-5.5 / +7.1 ns) on the two 0.10-pF input pins s_q[784] / s_q[1810].  As impl/r31/buf31.tcl.
set _blk [ord::get_db_block]; set _u [expr {double([$_blk getDefUnits])}]
set _bm [[ord::get_db] findMaster [qc_env QB37_IBCELL BUFFD2]]
set _thr [qc_env QB37_IBHPWL 300]; set _in [expr {round([qc_env QB37_IBIN 3] * $_u)}]
set _core [$_blk getCoreArea]
proc _hpwl37 {n} {
    set x0 1e18; set y0 1e18; set x1 -1e18; set y1 -1e18
    foreach t [$n getITerms] { set b [$t getBBox]; set x [$b xMin]; set y [$b yMin]
        set x0 [expr {min($x0,$x)}]; set y0 [expr {min($y0,$y)}]; set x1 [expr {max($x1,$x)}]; set y1 [expr {max($y1,$y)}] }
    foreach t [$n getBTerms] { foreach p [$t getBPins] { set b [$p getBBox]; set x [$b xMin]; set y [$b yMin]
        set x0 [expr {min($x0,$x)}]; set y0 [expr {min($y0,$y)}]; set x1 [expr {max($x1,$x)}]; set y1 [expr {max($y1,$y)}] } }
    expr {($x1 - $x0 + $y1 - $y0) / $::_u}
}
set _nb 0; set _names {}
foreach bt [$_blk getBTerms] {
    if {[$bt getIoType] ne "INPUT" || [$bt getSigType] ne "SIGNAL"} continue
    set n [$bt getNet]; if {$n eq "NULL" || [$n getSigType] ne "SIGNAL" || [llength [$n getITerms]] == 0} continue
    if {[string match clk* [$bt getName]] || [_hpwl37 $n] <= $_thr} continue
    set b [[lindex [$bt getBPins] 0] getBBox]
    set x [expr {([$b xMin] + [$b xMax]) / 2}]; set y [expr {([$b yMin] + [$b yMax]) / 2}]
    set x [expr {max([$_core xMin] + $_in, min([$_core xMax] - $_in - 2000, $x))}]
    set y [expr {max([$_core yMin] + $_in, min([$_core yMax] - $_in - 2000, $y))}]
    incr _nb
    set bi [odb::dbInst_create $_blk $_bm r37_ib_$_nb]; $bi setLocation $x $y; $bi setPlacementStatus PLACED
    set nn [odb::dbNet_create $_blk r37_ibn_$_nb]; $nn setSigType SIGNAL
    foreach it [$n getITerms] { $it disconnect; $it connect $nn }
    [$bi findITerm I] connect $n; [$bi findITerm Z] connect $nn
    lappend _names [$bt getName]
    lappend ::r37_newinst $bi; lappend ::r37_rip $n $nn
}
puts "R37_INBUF input-port buffers $_nb (HPWL > $_thr um, [$_bm getName]): $_names"
