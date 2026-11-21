# R37 (results/r37.md sec. 10): opt-in ICG clone for far sinks of a gated clock subtree, sourced by impl/r37/hubpre37.tcl when
# QB37_ICGCLONE = "<icg inst> <sink inst> ..." is set.  TritonCTS builds a gated net as its own tree hung under the ICG; the
# hub ICG clk_gate_g_wbc_ha_reg_7__7_ sits at x 3434 and its 4 sinks hct_reg_0/1, htp_reg_0/1 at x ~800, so they are
# clocked through a 2.6-mm 7-stage chain (tt 2.22 vs p50 1.67; ss 3.20 vs 2.43) and htp_reg_0 sets 26 ss setup endpoints.
# The clone (same master, same E / TE nets) is placed at the sinks' centroid, its CP on the main-tree clock net of the
# nearest ungated flop (clknet_*_clk), its Q on a new net to the listed sinks (their CP moved off the old net).
set _blk [ord::get_db_block]; set _u [expr {double([$_blk getDefUnits])}]
set _l $::env(QB37_ICGCLONE)
set _icg [$_blk findInst [lindex $_l 0]]
set _sinks {}; foreach s [lrange $_l 1 end] { set i [$_blk findInst $s]; if {$i ne "NULL"} { lappend _sinks $i } }
if {$_icg eq "NULL" || ![llength $_sinks]} { puts "R37_ICG nothing to do"; return }
set sx 0; set sy 0; foreach i $_sinks { set b [$i getBBox]; set sx [expr {$sx + [$b xMin]}]; set sy [expr {$sy + [$b yMin]}] }
set sx [expr {$sx / [llength $_sinks]}]; set sy [expr {$sy / [llength $_sinks]}]
# nearest flop whose CK net is driven by a main-tree leaf buffer
set best ""; set bd 1e18
foreach i [$_blk getInsts] {
    set m [$i getMaster]; if {![string match DF* [$m getName]]} continue
    set b [$i getBBox]; set d [expr {abs([$b xMin] - $sx) + abs([$b yMin] - $sy)}]; if {$d >= $bd} continue
    set it [$i findITerm CP]; if {$it eq "NULL"} continue; set n [$it getNet]; if {$n eq "NULL"} continue
    # main (ungated) tree nets are clknet_*_clk (gated subtrees: clknet_*_<icg net>)
    if {![string match clknet_*_clk [$n getName]]} continue
    set best $n; set bd $d
}
if {$best eq ""} { puts "R37_ICG no main-tree leaf net found"; return }
set _k 0; while {[$_blk findInst r37_icg_clone$_k] ne "NULL"} { incr _k }
set ci [odb::dbInst_create $_blk [$_icg getMaster] r37_icg_clone$_k]
$ci setLocation $sx $sy; $ci setPlacementStatus PLACED
foreach p {E TE} { set o [$_icg findITerm $p]; if {$o ne "NULL" && [$o getNet] ne "NULL"} { [$ci findITerm $p] connect [$o getNet] } }
[$ci findITerm CP] connect $best
set qn [odb::dbNet_create $_blk r37_icg_clone${_k}_q]; $qn setSigType CLOCK
[$ci findITerm Q] connect $qn
set _old [[[lindex $_sinks 0] findITerm CP] getNet]
foreach i $_sinks { set it [$i findITerm CP]; $it disconnect; $it connect $qn }
lappend ::r37_newinst $ci; lappend ::r37_rip $best $qn $_old
foreach p {E TE} { set o [$_icg findITerm $p]; if {$o ne "NULL" && [$o getNet] ne "NULL"} { lappend ::r37_rip [$o getNet] } }
puts [format "R37_ICG clone of %s at (%.1f %.1f) CP net %s (%.1f um from the centroid), sinks %d: %s" [$_icg getName] \
    [expr {$sx / $_u}] [expr {$sy / $_u}] [$best getName] [expr {$bd / $_u}] [llength $_sinks] [lmap i $_sinks {$i getName}]]
