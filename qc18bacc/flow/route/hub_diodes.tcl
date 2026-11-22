# Diode / antenna step of the hub (blocks/hub/run.sh dio, before DR; results/r29.md, r31.md, r34.md), in a run dir holding
# db/grt.{odb,sdc}; one file for impl/r29/dio29.tcl with its R34 hook impl/r34/dio_pre.tcl (r29/pdn29.tcl + r31/buf31.tcl):
#   1. macro-PDN strap trim (R29): the macro grids (floorplan/pdn_macro.tcl macro_rf: M4 1.0 um straps, pitch 20) run M4
#      over the macros' M1-M3 signal pins; a pin under a strap cannot take a VIA34, and an off-track pin then fails M3
#      NS-metal (results/r28.md).  For every macro and every vertical M4 power sbox over it, the strap is cut back so that
#      it stays 1.0 um clear (in y) of every signal pin whose x-range comes within 0.2 um of the strap; the vias in the
#      removed span are deleted; the strap keeps the longer remaining piece
#   2. macro-input buffers (R31): every macro signal input pin on a net whose pin HPWL exceeds 300 um (clock pins and
#      tie-driven nets skipped) gets its own BUFFD2 just outside the macro edge nearest to the pin (DPL legalises): the
#      long net then ends on the buffer input (gate 0.0546 um2 instead of the macro's 0.009).  Cause: the qb_p D pins fail
#      the cut-layer partial ratio (VIA78 / VIA89 28.8 vs 20) whenever DR reaches them from M8 / M9
#   3. diodes (R29) on the at-risk gate pins, inserted on the global-route solution (GRT 0.25 + QB15_GADJ_L, 50 congestion
#      iterations) and checked with check_antennas on the global-route wires with the LEF diffusion rule (scalar CAR of
#      M1-M8 set to 0 in memory, as signoff/antenna.tcl; restored before the db is written): every macro input pin on a
#      net with pin-bbox HPWL > 1000 um, every std-cell input pin on a macro-driven net above 1500 um, then 3 rounds of
#      check_antennas (GR wires) -> diodes (r34_dio_<n>) on the flagged pins -> incremental GRT
# Output: db/grt.{odb,sdc} (overwritten), route.guide, rpt/r29_dio_<k>.rpt.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set ::T0 [clock seconds]
qc_load grt
set_thread_count [qc_env QC_PNR_THREADS 16]
set blk [ord::get_db_block]; set u [expr {double([$blk getDefUnits])}]
set dm [[ord::get_db] findMaster [lindex $::QC_PNR_DIODE 0]]
# 1. macro-PDN strap trim
set _b [ord::get_db_block]; set _u [expr {double([$_b getDefUnits])}]
set _clr [expr {round(1.0 * $_u)}]; set _dx [expr {round(0.2 * $_u)}]
set _dry 0
set _m4 [[[ord::get_db] getTech] findLayer M4]
set _pins {}   ;# {x0 y0 x1 y1} of every macro signal pin (M1-M3), per macro bbox
set _mb {}
foreach i [$_b getInsts] {
    if {[[$i getMaster] getType] ne "BLOCK"} continue
    set bb [$i getBBox]; set ps {}
    foreach it [$i getITerms] {
        if {[[$it getMTerm] getSigType] ne "SIGNAL"} continue
        set ls [lsort -unique [concat {*}[lmap mp [[$it getMTerm] getMPins] {lmap bx [$mp getGeometry] {[$bx getTechLayer] getName}}]]]
        if {[lsearch $ls M4] >= 0 || ![llength $ls]} continue   ;# pins with M4 metal take the via in M4 itself
        set g [$it getBBox]; lappend ps [list [$g xMin] [$g yMin] [$g xMax] [$g yMax]]
    }
    lappend _mb [list [$bb xMin] [$bb yMin] [$bb xMax] [$bb yMax] $ps]
}
set _cut 0; set _vdel 0; set _hit 0
foreach net [$_b getNets] {
    if {![$net isSpecial] || [lsearch {POWER GROUND} [$net getSigType]] < 0} continue
    foreach sw [$net getSWires] {
        set vias {}; set straps {}
        foreach s [$sw getWires] {
            if {[$s isVia]} { lappend vias $s; continue }
            if {[$s getTechLayer] ne $_m4} continue
            if {[$s getDY] > [$s getDX]} { lappend straps $s }
        }
        foreach s $straps {
            set x0 [$s xMin]; set x1 [$s xMax]; set y0 [$s yMin]; set y1 [$s yMax]; set bad {}
            foreach m $_mb {
                lassign $m mx0 my0 mx1 my1 ps
                if {$x1 < $mx0 || $x0 > $mx1 || $y1 < $my0 || $y0 > $my1} continue
                foreach p $ps {
                    lassign $p px0 py0 px1 py1
                    if {$px1 + $_dx <= $x0 || $px0 - $_dx >= $x1 || $py1 < $y0 || $py0 > $y1} continue
                    lappend bad [list [expr {$py0 - $_clr}] [expr {$py1 + $_clr}]]
                }
            }
            if {![llength $bad]} continue
            incr _hit [llength $bad]
            # free intervals of [y0, y1] minus the pin bands; keep the longest
            set bad [lsort -integer -index 0 $bad]; set free {}; set c $y0
            foreach b $bad { lassign $b b0 b1; if {$b0 > $c} { lappend free [list $c $b0] }; set c [expr {max($c, $b1)}] }
            if {$c < $y1} { lappend free [list $c $y1] }
            set best {}; set bl -1
            foreach f $free { if {[lindex $f 1] - [lindex $f 0] > $bl} { set bl [expr {[lindex $f 1] - [lindex $f 0]}]; set best $f } }
            incr _cut
            if {$_dry || $best eq {}} continue
            lassign $best n0 n1
            foreach v $vias {
                set vx [expr {([$v xMin] + [$v xMax]) / 2}]; set vy [expr {([$v yMin] + [$v yMax]) / 2}]
                if {$vx < $x0 || $vx > $x1 || $vy < $y0 || $vy > $y1 || ($vy >= $n0 && $vy <= $n1)} continue
                if {[info exists _gone($v)]} continue
                set tv [$v getTechVia]; if {$tv eq "NULL"} { set tv [$v getBlockVia] }
                if {$tv eq "NULL" || [lsearch {M3 M4 M5 M6} [[$tv getBottomLayer] getName]] < 0} continue
                set _gone($v) 1; odb::dbSBox_destroy $v; incr _vdel
            }
            set st [$s getWireShapeType]
            odb::dbSBox_create $sw $_m4 $x0 $n0 $x1 $n1 $st
            odb::dbSBox_destroy $s
        }
    }
}
puts "R29_PDN straps trimmed $_cut (pin conflicts $_hit), M4 vias removed $_vdel, dry $_dry"
# 2. macro-input buffers
set _blk [ord::get_db_block]; set _u [expr {double([$_blk getDefUnits])}]
set _bm [[ord::get_db] findMaster BUFFD2]
set _thr 300; set _nb 0; set _cls {}
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
if {$_nb} { detailed_placement -max_displacement 500 }
# 3. diodes
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
foreach {l a} [qc_env QB15_GADJ_L ""] { set_global_routing_layer_adjustment $l $a }
global_route -congestion_iterations 50 -allow_congestion
set ::car0 {}
foreach ln {M1 M2 M3 M4 M5 M6 M7 M8} {
    set r [[[[ord::get_db] getTech] findLayer $ln] getDefaultAntennaRule]
    lappend ::car0 $r [$r getCAR]; $r setCAR 0
}
puts "R29_DIO grt done ([expr {[clock seconds] - $::T0}] s)"
set ::prot [dict create]; set ::nd 0
proc macro? {i} { expr {[[$i getMaster] getType] eq "BLOCK"} }
proc add_dio {it why} {
    set i [$it getInst]; set key "[$i getName]/[[$it getMTerm] getName]"
    if {[dict exists $::prot $key]} { return 0 }
    set n [$it getNet]; if {$n eq "NULL" || [$n getSigType] ne "SIGNAL"} { return 0 }
    dict set ::prot $key $why
    set b [$it getBBox]; set x [$b xMin]; set y [$b yMin]
    if {[macro? $i]} {   ;# start just outside the macro edge nearest to the pin; DPL legalises
        set m [$i getBBox]; set d [list [expr {$x - [$m xMin]}] [expr {[$m xMax] - $x}] [expr {$y - [$m yMin]}] [expr {[$m yMax] - $y}]]
        switch [lsearch $d [tcl::mathfunc::min {*}$d]] {
            0 { set x [expr {[$m xMin] - 4000}] } 1 { set x [expr {[$m xMax] + 2000}] }
            2 { set y [expr {[$m yMin] - 6000}] } 3 { set y [expr {[$m yMax] + 2000}] }
        }
    }
    set di [odb::dbInst_create [ord::get_db_block] $::dm r34_dio_[incr ::nd]]
    $di setLocation $x $y; $di setPlacementStatus PLACED
    [$di findITerm I] connect $n
    return 1
}
proc find_it {s} {
    set k [string last / $s]; set i [[ord::get_db_block] findInst [string range $s 0 [expr {$k - 1}]]]
    if {$i eq "NULL"} { return NULL }; return [$i findITerm [string range $s [expr {$k + 1}] end]]
}
proc rpt_pins {f} {
    set r {}; set g [open $f]
    while {[gets $g l] >= 0} { if {[regexp {^\s+Pin: (\S+) } $l -> s]} { lappend r $s } }
    close $g; return [lsort -unique $r]
}
proc hpwl {n} {
    set x0 1e18; set y0 1e18; set x1 -1e18; set y1 -1e18
    foreach t [$n getITerms] { lassign [$t getAvgXY] ok x y; if {!$ok} { set b [[$t getInst] getBBox]; set x [$b xMin]; set y [$b yMin] }
        set x0 [expr {min($x0,$x)}]; set y0 [expr {min($y0,$y)}]; set x1 [expr {max($x1,$x)}]; set y1 [expr {max($y1,$y)}] }
    expr {($x1 - $x0 + $y1 - $y0) / $::u}
}
global_route -start_incremental
set c [dict create seed 0 hpwl 0 shpwl 0]
set H 1000; set SH 1500
foreach i [$blk getInsts] {
    if {![macro? $i]} continue
    foreach it [$i getITerms] {
        set n [$it getNet]; if {$n eq "NULL" || [$n getSigType] ne "SIGNAL"} continue
        if {$H > 0 && [$it isInputSignal] && [hpwl $n] > $H} { dict incr c hpwl [add_dio $it hpwl] }
        if {$SH > 0 && [$it isOutputSignal] && [hpwl $n] > $SH} {
            foreach t [$n getITerms] {
                if {[$t isInputSignal] && ![macro? [$t getInst]] && [[$t getInst] getMaster] ne $::dm} { dict incr c shpwl [add_dio $t shpwl] }
            }
        }
    }
}
puts "R29_DIO pre-insert seed [dict get $c seed] hpwl [dict get $c hpwl] shpwl [dict get $c shpwl] ([expr {[clock seconds] - $::T0}] s)"
proc legal_route {} {
    detailed_placement -max_displacement 500
    global_route -end_incremental
}
if {$::nd > 0} { legal_route }
for {set k 0} {$k <= 3} {incr k} {
    set f $::OUT/rpt/r29_dio_$k.rpt
    check_antennas -report_file $f
    set ps [rpt_pins $f]
    puts "R29_DIO round $k: GR-wire antenna pins [llength $ps], diodes so far $::nd ([expr {[clock seconds] - $::T0}] s)"
    if {![llength $ps] || $k == 3} break
    global_route -start_incremental
    set a 0; foreach s $ps { set it [find_it $s]; if {$it ne "NULL"} { incr a [add_dio $it gr$k] } }
    if {$a == 0} { global_route -end_incremental; puts "R29_DIO round $k: all flagged pins already have a diode"; break }
    legal_route
}
if {[catch {check_placement} e]} { puts "R29_DIO check_placement: $e" }
foreach {r v} $::car0 { $r setCAR $v }
write_guides $::OUT/route.guide
qc_save grt
qc_summary "r29 dio diodes $::nd final_gr_antenna_pins [llength $ps]"
puts "R29_DIO done diodes $::nd ([expr {[clock seconds] - $::T0}] s)"
exit
