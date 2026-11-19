# R27 (results/r27.md): place-step repair attribution of a run (QC_PNR_OUT): instances of db/[QB27_DB place].odb not in
# db/pdn.odb = inserted (tie cells counted apart), same name with another master = resized.  Every inserted buffer is
# traced up to its root (the original net, driven by an original cell or an input port).  One line per root net (plus
# the output net of every resized original cell) -> $QB27_OUT.trees: T root_net drv_inst drv_master nbuf buf_um2
# rsz_um2 hpwl_um maxdist_um span nsinks net_stem drv_stem top_sink_stem (non-anonymous; M:<macro>.<pin>, P:<port>) count.
# stem: drop u_top_, keep the first hierarchy level, drop [i] and _reg, digits -> N, drop _N runs (anonymous DC cells / nets: UN, nN, netN).  span 1: the net bbox covers the full height of a macro row it overlaps in x.
# Stage QB27_STAGE pdn: writes $QB27_OUT.pdn (inst master) only.  Summary lines R27_A*.  No liberty / timing needed.
set out $::env(QB27_OUT); set d $::env(QC_PNR_OUT)/db
if {[info exists ::env(QB27_STAGE)] && $::env(QB27_STAGE) eq "pdn"} {
    read_db $d/pdn.odb
    set f [open $out.pdn w]
    foreach i [[ord::get_db_block] getInsts] { puts $f "[$i getName] [[$i getMaster] getName]" }
    close $f; puts "R27_APDN [llength [[ord::get_db_block] getInsts]]"; exit
}
read_db $d/[expr {[info exists ::env(QB27_DB)] ? $::env(QB27_DB) : "place"}].odb
set blk [ord::get_db_block]; set db [ord::get_db]
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set f [open $out.pdn]; while {[gets $f l] >= 0} { set P([lindex $l 0]) [lindex $l 1] }; close $f
proc marea {m} { return [expr {[$m getWidth] * [$m getHeight] / $::u / $::u}] }
array set NEW {}; array set RSZ {}; set ntie 0; set atie 0.0; set nrm 0; array set BM {}
set rows {}
foreach i [$blk getInsts] {
    set m [$i getMaster]; set n [$i getName]
    if {[$m isBlock]} { set b [$i getBBox]; lappend rows [list [$b yMin] [$b yMax] [$b xMin] [$b xMax]]; continue }
    if {![info exists P($n)]} {
        if {[string match TIE* [$m getName]]} { incr ntie; set atie [expr {$atie + [marea $m]}]; continue }
        set NEW($n) [marea $m]; set k [$m getName]
        set BM($k) [expr {[info exists BM($k)] ? $BM($k) + 1 : 1}]
    } elseif {$P($n) ne [$m getName]} {
        set RSZ($n) [expr {[marea $m] - [marea [$db findMaster $P($n)]]}]
    }
}
# macro rows: blocks grouped by yMin
array set MR {}
foreach r $rows { lassign $r y0 y1 x0 x1; if {[info exists MR($y0)]} { lassign $MR($y0) a b c e; set MR($y0) [list [expr {min($a,$y0)}] [expr {max($b,$y1)}] [expr {min($c,$x0)}] [expr {max($e,$x1)}]] } else { set MR($y0) [list $y0 $y1 $x0 $x1] } }
puts "R27_AROWS [llength [array names MR]] macro rows (blocks [llength $rows])"
proc outnet {i} { foreach it [$i getITerms] { if {[$it isOutputSignal] && [$it getNet] ne "NULL"} { return [$it getNet] } }; return NULL }
proc innet {i} { foreach it [$i getITerms] { if {[$it isInputSignal] && [$it getNet] ne "NULL"} { return [$it getNet] } }; return NULL }
proc drv {net} {
    foreach it [$net getITerms] { if {[$it isOutputSignal]} { return [list I [$it getInst]] } }
    foreach bt [$net getBTerms] { if {[$bt getIoType] eq "INPUT"} { return [list P $bt] } }
    return [list X NULL]
}
array set R {}
proc root {n} {
    if {[info exists ::R($n)]} { return $::R($n) }
    set net [innet [$::blk findInst $n]]
    if {$net eq "NULL"} { set ::R($n) NULL; return NULL }
    lassign [drv $net] k o
    if {$k eq "I" && [info exists ::NEW([$o getName])]} { set r [root [$o getName]] } else { set r [$net getName] }
    set ::R($n) $r; return $r
}
array set ROOT {}; array set NB {}; array set AB {}
foreach n [array names NEW] {
    set r [root $n]; set ROOT($r) 1
    set NB($r) [expr {[info exists NB($r)] ? $NB($r) + 1 : 1}]; set AB($r) [expr {[info exists AB($r)] ? $AB($r) + $NEW($n) : $NEW($n)}]
}
array set AR {}
foreach n [array names RSZ] {
    set net [outnet [$blk findInst $n]]; if {$net eq "NULL"} continue
    set r [$net getName]; set ROOT($r) 1; set AR($r) [expr {[info exists AR($r)] ? $AR($r) + $RSZ($n) : $RSZ($n)}]
}
proc cen {o} { set b [$o getBBox]; return [list [expr {([$b xMin] + [$b xMax]) / 2.0 / $::u}] [expr {([$b yMin] + [$b yMax]) / 2.0 / $::u}]] }
proc stem {n} {
    regsub {^u_top_} $n {} n; set n [lindex [split $n /] 0]
    regsub -all {\[[0-9]+\]} $n {} n; regsub -all {_reg(_|$)} $n {\1} n; regsub -all {[0-9]+} $n N n
    regsub -all {(_N)+(_|$)} $n {\2} n; return [string trimright $n _]
}
proc sinks {net} {
    set s {}
    foreach it [$net getITerms] {
        if {![$it isInputSignal]} continue
        set i [$it getInst]
        if {[info exists ::NEW([$i getName])]} { set o [outnet $i]; if {$o ne "NULL"} { lappend s {*}[sinks $o] } } elseif {[[$i getMaster] isBlock]} {
            lappend s [list {*}[cen $i] M:[string range [[$i getMaster] getName] 0 3].[stem [[$it getMTerm] getName]]] } else { lappend s [list {*}[cen $i] [stem [$i getName]]] }
    }
    foreach bt [$net getBTerms] { if {[$bt getIoType] eq "OUTPUT"} { lappend s [list {*}[cen $bt] P:[stem [$bt getName]]] } }
    return $s
}
set f [open $out.trees w]
foreach r [array names ROOT] {
    set net [$blk findNet $r]; if {$net eq "NULL"} continue
    lassign [drv $net] k o
    if {$k eq "I"} { set dn [$o getName]; set dm [[$o getMaster] getName]; set dp [cen $o] } elseif {$k eq "P"} { set dn PORT:[$o getName]; set dm PORT; set dp [cen $o] } else { set dn NONE; set dm NONE; set dp {0 0} }
    set ss [sinks $net]; lassign $dp x0 y0; set xa $x0; set xb $x0; set ya $y0; set yb $y0; set md 0.0; array unset SK
    foreach p $ss { lassign $p x y st; set SK($st) [expr {[info exists SK($st)] ? $SK($st) + 1 : 1}]; set xa [expr {min($xa,$x)}]; set xb [expr {max($xb,$x)}]; set ya [expr {min($ya,$y)}]; set yb [expr {max($yb,$y)}]; set md [expr {max($md, abs($x-$x0)+abs($y-$y0))}] }
    set sp 0
    foreach k2 [array names MR] { lassign $MR($k2) ry0 ry1 rx0 rx1
        if {$ya * $u <= $ry0 && $yb * $u >= $ry1 && $xb * $u > $rx0 && $xa * $u < $rx1} { set sp 1; break } }
    set sk -; set skn 0; foreach {a b} [array get SK] { if {![regexp {^(UN|nN|netN|N|U)$} $a] && $b > $skn} { set sk $a; set skn $b } }
    puts $f [format "T %s %s %s %d %.2f %.2f %.1f %.1f %d %d %s %s %s %d" $r $dn $dm [expr {[info exists NB($r)] ? $NB($r) : 0}] \
        [expr {[info exists AB($r)] ? $AB($r) : 0}] [expr {[info exists AR($r)] ? $AR($r) : 0}] [expr {$xb-$xa+$yb-$ya}] $md $sp [llength $ss] [stem $r] [stem [string map {PORT: {}} $dn]] $sk $skn]
}
close $f
set ab 0.0; foreach n [array names NEW] { set ab [expr {$ab + $NEW($n)}] }
set ar 0.0; set arp 0.0; set arn 0.0; foreach n [array names RSZ] { set ar [expr {$ar + $RSZ($n)}]; if {$RSZ($n) > 0} { set arp [expr {$arp + $RSZ($n)}] } else { set arn [expr {$arn + $RSZ($n)}] } }
foreach n [array names P] { if {[$blk findInst $n] eq "NULL"} { incr nrm } }
puts [format "R27_ATOT inserted %d / %.1f um2, resized %d net %.1f um2 (+%.1f / %.1f), tie %d / %.1f um2, removed (pre-place remove_buffers) %d, roots %d" \
    [array size NEW] $ab [array size RSZ] $ar $arp $arn $ntie $atie $nrm [array size ROOT]]
puts "R27_ABUF [lsort -stride 2 -index 1 -integer -decreasing [array get BM]]"
