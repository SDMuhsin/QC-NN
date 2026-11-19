# R29 (results/r29.md): opt-in macro-PDN strap trim (sourced by impl/r29/dio29.tcl via R29_PDN, or stand-alone after
# read_db).  The macro grids (impl/r5b/pdn_macro.tcl macro_rf: M4 1.0 um straps, pitch 20, over the macro) run M4 over
# the macros' M1-M3 signal pins; a pin under a strap cannot take a VIA34, and an off-track pin then fails M3 NS-metal
# (results/r28.md).  For every macro (BLOCK) and every vertical M4 power sbox over it, the strap is cut back so that it
# stays R29_PDN_CLR um [1.0] clear (in y) of every signal pin whose x-range comes within 0.2 um of the strap; the vias
# in the removed span are deleted.  The strap keeps the longer remaining piece.  R29_PDN_DRY 1: report only.
set _b [ord::get_db_block]; set _u [expr {double([$_b getDefUnits])}]
set _clr [expr {round([qc_env R29_PDN_CLR 1.0] * $_u)}]; set _dx [expr {round(0.2 * $_u)}]
set _dry [qc_env R29_PDN_DRY 0]
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
