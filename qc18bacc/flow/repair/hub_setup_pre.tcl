# Hub QB37_HPRE_TCL hook of repair/hold_eco.tcl (results/r37.md sec. 9, r38.md, r40.md): a setup repair against the
# QB35_IO_TCL constraints (repair/hub_io.tcl) at every loaded corner before the hold repair.
# Knobs (blocks/hub/run.sh hold): QB37_RESIZE, QB37_PORTBUF_UP, QB37_DONTTOUCH, QB37_SM,
# QB37_SPCT, QB37_HUNC.
proc _w37 {tag} {
    set s [sta::worst_slack_corner [sta::find_corner tt] max]; set ns NA; catch { set ns [sta::endpoint_violation_count max] }
    puts [format "R37_HPRE %s setup_wns %.3f setup_viol %s" $tag [expr {$s * 1e9}] $ns]
}
# QB37_RESIZE "<inst> <master> ...": e.g. a port buffer upsized for the LEF-rule antenna ratio of its long input net
foreach {_i _m} [qc_env QB37_RESIZE ""] {
    set _ii [[ord::get_db_block] findInst $_i]; set _mm [[ord::get_db] findMaster $_m]
    if {$_ii eq "NULL" || $_mm eq "NULL"} { puts "R37_HPRE resize: no $_i / $_m"; continue }
    $_ii swapMaster $_mm
    puts "R37_HPRE resized $_i -> $_m"
}
_w37 pre_setup
# QB37_PORTBUF_UP "<um> <master>": every input-port buffer of master BUFFD1 / BUFFD2 / BUFFD4 whose port net is longer than
# <um> (Manhattan port pin -> buffer) is upsized to <master>: gate area for the LEF-rule antenna ratio of the long port
# net, which an incremental re-route of all port nets may put on M8 / M9 (r35_hubC ECO 2 / 4: 1-2 such nets each time)
if {[llength [qc_env QB37_PORTBUF_UP ""]] == 2} {
    lassign [qc_env QB37_PORTBUF_UP ""] _lim _mn; set _mm [[ord::get_db] findMaster $_mn]; set _uu [expr {double([[ord::get_db_block] getDefUnits])}]; set _nu 0
    foreach bt [[ord::get_db_block] getBTerms] {
        if {[$bt getIoType] ne "INPUT"} continue
        set n [$bt getNet]; if {$n eq "NULL" || [$n getSigType] ne "SIGNAL" || [llength [$n getITerms]] != 1} continue
        set it [lindex [$n getITerms] 0]; set i [$it getInst]
        if {[lsearch {BUFFD1 BUFFD2 BUFFD4} [[$i getMaster] getName]] < 0} continue
        set b [[lindex [$bt getBPins] 0] getBBox]; set c [$i getBBox]
        if {(abs([$c xMin] - [$b xMin]) + abs([$c yMin] - [$b yMin])) / $_uu <= $_lim} continue
        $i swapMaster $_mm; incr _nu
    }
    puts "R37_HPRE port buffers upsized to $_mn: $_nu (port net > $_lim um)"
}
# QB37_DONTTOUCH "<inst> ...": cells the setup repair must not resize (r35_hubC ECO 4: INR2XD2 -> INR2XD4 U92356 made DRT
# fail on its A1 pin access, DRT-0218, with and without its neighbours' wires ripped)
foreach _i [qc_env QB37_DONTTOUCH ""] { set_dont_touch [get_cells $_i]; puts "R37_HPRE dont_touch $_i" }
# snapshot (name -> master): the cells the setup repair adds or resizes are listed
set _m0 [dict create]; foreach i [[ord::get_db_block] getInsts] { dict set _m0 [$i getName] [[$i getMaster] getName] }
set _t [clock seconds]
if {[catch { repair_timing -setup -setup_margin [qc_env QB37_SM 0.0] -max_utilization 95 \
        -max_buffer_percent [qc_env QB37_SPCT 5] -skip_pin_swap -skip_gate_cloning } e]} { puts "R37_HPRE setup repair stopped: $e" }
puts "R37_HPRE repair_timing -setup [expr {[clock seconds] - $_t}] s"
_w37 post_setup
set _ns 0
foreach i [[ord::get_db_block] getInsts] {
    set k [$i getName]
    if {[dict exists $_m0 $k] && [dict get $_m0 $k] eq [[$i getMaster] getName]} continue
    incr _ns; puts "R37_HPRE changed [$i getName] [[$i getMaster] getName]"
}
puts "R37_HPRE setup repair added / resized $_ns cells"
# output hold windows loosened by the hold margin (output -min = -L + QB35_HOLD_M), as repair/act_hold_pre.tcl, so the
# hold margin acts on reg2reg / in2reg only
# (several corners: through the per-corner re-anchoring of the IO budget, repair/io_ref.tcl)
set _cmd [list set_output_delay -min [expr {-$::env(QB35_IOL) + [qc_env QB35_HOLD_M 0.0]}] -clock qb_clk [all_outputs]]
if {[info exists ::qb_io_ref_P]} { qb_io_ref_eval $_cmd } else { eval $_cmd }
puts "R37_HPRE output -min delay = -L + [qc_env QB35_HOLD_M 0.0]"
# QB37_HUNC "<pin pattern> <extra ns> ...": extra hold uncertainty on capture clock pins of the PT residual hold endpoints,
# so the hold repair gives those paths a larger margin than the global one (incremental re-route slip on them)
foreach {_p _x} [qc_env QB37_HUNC ""] {
    set _ps [get_pins -quiet $_p]
    if {![llength $_ps]} { puts "R37_HPRE hunc: no pins $_p"; continue }
    set_clock_uncertainty -hold [expr {0.05 + $_x}] $_ps
    puts "R37_HPRE hold uncertainty +$_x on [llength $_ps] pins ($_p)"
}
