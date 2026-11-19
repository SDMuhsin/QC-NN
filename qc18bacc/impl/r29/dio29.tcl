# R29 (results/r29.md): opt-in antenna fix before DR.  Diodes on the at-risk gate pins, inserted on the global-route
# solution and checked with check_antennas on the global-route wires (it flags what DR's check flags; GRT's own
# repair_antennas finds only a handful).  In a run dir holding db/grt.{odb,sdc} (impl/r29/run29.sh dio <tag>):
#   R29_SEED   file of "inst/pin" lines protected unconditionally (e.g. the pins of a previous DR antenna report)
#   R29_HPWL   <um> [0 = off]: also every macro input pin on a net whose pin-bbox HPWL exceeds it
#   R29_SHPWL  <um> [0 = off]: also every std-cell input pin without diffusion on a macro-driven net above it
#   R29_LOOPS  [3] rounds of check_antennas (GR wires) -> diodes on the flagged pins -> incremental GRT
#   R29_PDN    [""] tcl sourced after loading (e.g. impl/r29/pdn29.tcl, the macro-PDN strap trim)
#   R29_ANTD   [0] 1: the GR-wire checks apply the LEF diffusion rule (scalar CAR of M1-M8 set to 0 in memory, as
#              impl/r29/antd29.tcl; restored before the db is written)
# Output: db/grt.{odb,sdc} (overwritten; the input is kept as db/grt_r29in.*), route.guide, rpt/r29_dio_<k>.rpt.
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
if {[qc_env R29_PDN ""] ne ""} { source [qc_env R29_PDN ""] }
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
foreach {l a} [qc_env QB15_GADJ_L ""] { set_global_routing_layer_adjustment $l $a }
global_route -congestion_iterations [p GR_ITER] -allow_congestion
set ::car0 {}
if {[qc_env R29_ANTD 0]} {
    foreach ln {M1 M2 M3 M4 M5 M6 M7 M8} {
        set r [[[[ord::get_db] getTech] findLayer $ln] getDefaultAntennaRule]
        lappend ::car0 $r [$r getCAR]; $r setCAR 0
    }
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
    set di [odb::dbInst_create [ord::get_db_block] $::dm r29_dio_[incr ::nd]]
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
if {[qc_env R29_SEED ""] ne ""} {
    set g [open [qc_env R29_SEED ""]]
    while {[gets $g l] >= 0} { if {[llength $l] == 1} { set it [find_it $l]; if {$it ne "NULL"} { dict incr c seed [add_dio $it seed] } } }
    close $g
}
set H [qc_env R29_HPWL 0]; set SH [qc_env R29_SHPWL 0]
if {$H > 0 || $SH > 0} {
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
}
puts "R29_DIO pre-insert seed [dict get $c seed] hpwl [dict get $c hpwl] shpwl [dict get $c shpwl] ([expr {[clock seconds] - $::T0}] s)"
proc legal_route {} {
    detailed_placement {*}[qc_env R29_DPL_ARGS "-max_displacement 500"]
    global_route -end_incremental
}
if {$::nd > 0} { legal_route }
for {set k 0} {$k <= [qc_env R29_LOOPS 3]} {incr k} {
    set f $::OUT/rpt/r29_dio_$k.rpt
    check_antennas -report_file $f
    set ps [rpt_pins $f]
    puts "R29_DIO round $k: GR-wire antenna pins [llength $ps], diodes so far $::nd ([expr {[clock seconds] - $::T0}] s)"
    if {![llength $ps] || $k == [qc_env R29_LOOPS 3]} break
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
