# PRE_CTS_TCL of impl/r14/top14.cfg: scripted top clock skeleton, TritonCTS only on the leaf nets (results/r14.md 4).
# R11: plain TritonCTS built its H-tree over the hard blocks (CKBD16 driving 0.7-1.3 pF of 1-3-mm wire per stage,
# skew 5.97 ns) and -insertion_delay traced only 2 clock nets.  Here the tree is split at the block boundaries:
#   chip clk pin (gap west edge) -> R (CKBD16, gap) -> { H: hub clk pin (west strip, M8), A: act clk pin (act south
#   edge), G: leaf root of the gap sinks (sequencer / host regs), U: riser }
#   U (CKBD16, gap top) -> 2-mm M8 net over the act block (dont_touch: no site along it; thick-metal RC checked at
#   GRT) -> N0 (CKBD16, north band above the act block) -> spine net east along the band ->
#   { C_c (CKBD8) at each column clk pin (north edge, c = 0..7), L_nw / L_k (k = 0..3, two columns each): leaf roots }
# TritonCTS then runs with -clk_nets = the leaf nets (G, L_*) + the ICG output nets below them; the skeleton nets
# are not touched by it.  Balancing against the block insertion delays (column 0.96 / hub 0.90 / act 0.55 ns tt)
# is impl/r14/bal14.tcl (PRE_ROUTE: delay chains in front of the earlier branches).
set _b [ord::get_db_block]; set _db [ord::get_db]; set _u [$_b getDefUnits]
proc q14_um {v} { return [expr {int(round($v * $::_u))}] }
proc q14_buf {name master x y} {
    set i [odb::dbInst_create $::_b [$::_db findMaster $master] $name]
    $i setLocation [q14_um $x] [q14_um $y]; $i setPlacementStatus PLACED
    return $i
}
proc q14_net {name} { return [odb::dbNet_create $::_b $name] }
proc q14_pin {i p} { return [$i findITerm $p] }
lassign $::QB11_ACT _ax1 _ay1 _ax2 _ay2
set _x0 $::QB14_X0; set _yh $::QB11_YH; set _yt $::QB11_YT
set _ck [[$_b findBTerm clk] getNet]
# sinks of the clock net, by region / section
array set _grp {}; set _gated {}
set _hub ""; set _act ""; array set _col {}
foreach t [$_ck getITerms] {
    set i [$t getInst]; set m [[$i getMaster] getName]
    if {$m eq "qb_hub"} { set _hub $t; continue }
    if {$m eq "qb_act2_blk"} { set _act $t; continue }
    if {$m eq "qb_col_blk"} { regexp {g_c_(\d+)_} [$i getName] -> c; set _col($c) $t; continue }
    set bb [$i getBBox]; set x [expr {([$bb xMin] + [$bb xMax]) / 2.0 / $_u}]; set y [expr {([$bb yMin] + [$bb yMax]) / 2.0 / $_u}]
    if {$x < $_x0 && $y < $_ay1} { set g gap } elseif {$x < $_x0} { set g nw } else { set g n[expr {min(3, int(($x - $_x0) / 780.0))}] }
    # ICG clock pins on their own leaf (<g>i): gated flops sit one ICG + one subtree later than the ungated ones, so
    # bal14.tcl balances the two leaves of a region separately (clk14.tcl reads rpt/q14_gated.txt)
    if {[string match CKLN* $m]} {
        set q [$i findITerm Q]
        if {$q ne "NULL" && [$q getNet] ne "NULL"} { foreach _s [[$q getNet] getITerms] { if {[$_s isInputSignal]} { lappend _gated [list [[$_s getInst] getName] ${g}i] } } }
        set g ${g}i
    }
    lappend _grp($g) [list $t $x $y]
}
set _gf [open $::OUT/rpt/q14_gated.txt w]; foreach e $_gated { puts $_gf [join $e " "] }; close $_gf
qc_log "r14 cts14: sinks hub [expr {$_hub ne ""}] act [expr {$_act ne ""}] cols [array size _col] groups [join [lmap g [lsort [array names _grp]] {format "%s %d" $g [llength $_grp($g)]}] {, }]"
proc q14_pinxy {t} {
    lassign [$t getAvgXY] ok x y
    if {$ok} { return [list [expr {$x / double($::_u)}] [expr {$y / double($::_u)}]] }
    set bb [[$t getInst] getBBox]; return [list [expr {([$bb xMin] + [$bb xMax]) / 2.0 / $::_u}] [expr {([$bb yMin] + [$bb yMax]) / 2.0 / $::_u}]]
}
# chip clk pin location
set _bt [$_b findBTerm clk]; set _bx 0; set _by [expr {($_yh + $_ay1) / 2}]
foreach bp [$_bt getBPins] { set bb [$bp getBBox]; set _bx [expr {[$bb xMin] / double($_u)}]; set _by [expr {[$bb yMin] / double($_u)}] }
# skeleton
foreach t [$_ck getITerms] { $t disconnect }
set R [q14_buf q14_R CKBD16 [expr {$_bx + 20}] $_by]
[q14_pin $R I] connect $_ck
set nR [q14_net q14_nR]; [q14_pin $R Z] connect $nR
set ym [expr {$_yt + 50.0}]
proc q14_tap {name master x y drvnet sinkterm} {
    set i [q14_buf $name $master $x $y]; [q14_pin $i I] connect $drvnet
    set n [q14_net ${name}_n]; [q14_pin $i Z] connect $n
    if {$sinkterm ne ""} { $sinkterm connect $n }
    return $i
}
lassign [q14_pinxy $_hub] hx hy
set H [q14_tap q14_H CKBD8 $hx [expr {$hy + 8}] $nR $_hub]
lassign [q14_pinxy $_act] ax ay
set A [q14_tap q14_A CKBD8 $ax [expr {$ay - 10}] $nR $_act]
set U [q14_tap q14_U CKBD16 450.0 [expr {$_ay1 - 12}] $nR ""]
set nU [[q14_pin $U Z] getNet]
set N0 [q14_tap q14_N0 CKBD16 450.0 $ym $nU ""]
set nS [[q14_pin $N0 Z] getNet]
foreach c [lsort -integer [array names _col]] {
    lassign [q14_pinxy $_col($c)] cx cy
    q14_tap q14_C$c CKBD8 $cx [expr {$cy + 6}] $nS $_col($c)
}
set ::Q14_LEAF {}
foreach g [lsort [array names _grp]] {
    set sx 0; set sy 0
    foreach e $_grp($g) { set sx [expr {$sx + [lindex $e 1]}]; set sy [expr {$sy + [lindex $e 2]}] }
    set n [llength $_grp($g)]; set cx [expr {$sx / $n}]; set cy [expr {$sy / $n}]
    if {[string match gap* $g]} { set drv $nR } else { set drv $nS; if {$cy < $_yt + 5} { set cy [expr {$_yt + 20}] } }
    set L [q14_tap q14_L$g CKBD16 $cx $cy $drv ""]
    set nl [[q14_pin $L Z] getNet]
    foreach e $_grp($g) { [lindex $e 0] connect $nl }
    lappend ::Q14_LEAF [$nl getName]
    # ICG outputs below this leaf: TritonCTS builds their trees too
    foreach e $_grp($g) {
        set i [[lindex $e 0] getInst]
        if {[string match CKLN* [[$i getMaster] getName]]} {
            set q [$i findITerm Q]
            if {$q ne "NULL" && [$q getNet] ne "NULL"} { lappend ::Q14_LEAF [[$q getNet] getName] }
        }
    }
}
# the riser over the act block has no site along it: out of repair_clock_nets / repair (thick M8, checked at GRT)
# (set after TritonCTS: TritonCTS disconnects / reconnects clock iterms itself, ODB-0372 on a dont_touch net)
set ::Q14_RISER [$nU getName]
if {[info commands q14_cts_orig] eq ""} {
    rename clock_tree_synthesis q14_cts_orig
    proc clock_tree_synthesis {args} {
        q14_cts_orig {*}$args
        qc_log "r14 cts14: TritonCTS done (riser $::Q14_RISER left to repair_clock_nets: its long-wire buffers land on the act edge)"
    }
}
foreach n [list $nR $nU $nS] { $n setSigType CLOCK }
qc_log "r14 cts14: skeleton R H A U N0 + [array size _col] column taps + [llength [array names _grp]] leaf roots; TritonCTS -clk_nets [llength $::Q14_LEAF] nets"
set P(CTS_ARGS) [concat [p CTS_ARGS] [list -clk_nets [join $::Q14_LEAF " "]]]
# legalise the skeleton cells before TritonCTS
detailed_placement {*}[p DPL_ARGS]
estimate_parasitics -placement
