# impl/r6b/run.sh grp: standalone global placement of one R6a group (QB_GRP) of top standard cells inside its floorplan
# rectangles (<run>/mplace.tcl.groups), on the chip database db/pdn.odb (after prep), which is not written back:
# the group's cells (and cells of no group) are movable; every other standard cell is removed and replaced, on each
# net it shares with the group, by one fixed anchor pin (a BTerm without area) at the centroid of its removed cells'
# seed positions (QB_SEED: a previous pass, <dir>/grp_<g>.pos; else uniform random inside their group's rectangles);
# blocks / macros / chip pins fixed as placed; placement blockages = the row segments outside the group's rectangles
# (rows are already cut under macros + halos, so no area is counted twice by gpl's density: a first version with
# FIRM seed cells + rectangle blockages failed GPL-0301 / 0302, whitespace counted negative).
# Output <run>/grp_<G>.pos: '<inst> <x> <y>' (dbu) of the group's cells + a line of statistics.
set ::OUT $::env(QC_PNR_OUT)
set G $::env(QB_GRP)
set_thread_count [expr {[info exists ::env(QC_PNR_THREADS)] ? $::env(QC_PNR_THREADS) : 4}]
read_db $::OUT/db/pdn.odb
set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
set core [$blk getCoreArea]
array set R {}
set f [open $::OUT/mplace.tcl.groups]
while {[gets $f l] >= 0} {
    set w [split [string trim $l] " "]
    set R([lindex $w 0]) {}
    foreach {a b c d} [lrange $w 1 end] {
        lappend R([lindex $w 0]) [list [expr {max([$core xMin], round($a * $u))}] [expr {max([$core yMin], round($b * $u))}] \
            [expr {min([$core xMax], round($c * $u))}] [expr {min([$core yMax], round($d * $u))}]]
    }
}
close $f
array set grp {}
set f [open $::env(QB_GFILE)]
while {[gets $f l] >= 0} { set w [split $l " "]; set grp([lindex $w 0]) [lindex $w 1] }
close $f
array set seed {}
foreach g [array names R] {
    if {$g eq $G || ![info exists ::env(QB_SEED)] || ![file exists $::env(QB_SEED)/grp_$g.pos]} continue
    set f [open $::env(QB_SEED)/grp_$g.pos]
    while {[gets $f l] >= 0} { set w [split $l " "]; if {[llength $w] >= 3} { set seed([lindex $w 0]) [lrange $w 1 2] } }
    close $f
}
proc inrect {rs x y} {
    foreach r $rs { lassign $r a b c d; if {$x >= $a && $x < $c && $y >= $b && $y < $d} { return 1 } }
    return 0
}
# area-weighted random point in a group's rectangles
proc rpt {rs} {
    set tot 0.0; foreach r $rs { lassign $r a b c d; set tot [expr {$tot + double($c - $a) * ($d - $b)}] }
    set t [expr {rand() * $tot}]
    foreach r $rs {
        lassign $r a b c d; set ar [expr {double($c - $a) * ($d - $b)}]
        if {$t <= $ar} { return [list [expr {$a + int(rand() * ($c - $a))}] [expr {$b + int(rand() * ($d - $b))}]] }
        set t [expr {$t - $ar}]
    }
    return [list $a $b]
}
expr {srand(6)}
set nG 0; set nX 0; set aM 0.0; set kill {}; set mac {}
array set sx {}; array set sy {}; array set sn {}; array set gnet {}
foreach i [$blk getInsts] {
    set m [$i getMaster]
    if {[$m isBlock]} { lappend mac $i; continue }
    set n [$i getName]
    set g [expr {[info exists grp($n)] ? $grp($n) : "X"}]
    if {$g eq $G || $g eq "X" || ![info exists R($g)]} {
        $i setPlacementStatus UNPLACED
        set aM [expr {$aM + double([$m getWidth]) * [$m getHeight]}]
        if {$g eq $G} { incr nG } else { incr nX }
        foreach it [$i getITerms] { set nt [$it getNet]; if {$nt ne "NULL" && $nt ne ""} { set gnet($nt) 1 } }
    } else {
        if {[info exists seed($n)]} { lassign $seed($n) x y } else { lassign [rpt $R($g)] x y }
        foreach it [$i getITerms] {
            set nt [$it getNet]
            if {$nt eq "NULL" || $nt eq "" || [$nt getSigType] ne "SIGNAL"} continue
            if {[info exists sn($nt)]} { set sx($nt) [expr {$sx($nt) + $x}]; set sy($nt) [expr {$sy($nt) + $y}]; incr sn($nt) } else { set sx($nt) $x; set sy($nt) $y; set sn($nt) 1 }
        }
        lappend kill $i
    }
}
set lay [[ord::get_db_tech] findLayer M3]
set na 0
foreach nt [array names sn] {
    if {![info exists gnet($nt)] || $sn($nt) > 2000} continue
    set x [expr {round($sx($nt) / $sn($nt))}]; set y [expr {round($sy($nt) / $sn($nt))}]
    set bt [odb::dbBTerm_create $nt qb6_anchor_[incr na]]
    $bt setIoType INPUT
    set bp [odb::dbBPin_create $bt]
    odb::dbBox_create $bp $lay $x $y [expr {$x + 100}] [expr {$y + 100}]
    $bp setPlacementStatus FIRM
}
# blocks / macros: one fixed anchor pin per pin on a net of the group (gpl rejects fixed instances taller than its
# core, GPL-0119), then removed as well
set nm 0
foreach i $mac {
    foreach it [$i getITerms] {
        set nt [$it getNet]
        if {$nt eq "NULL" || $nt eq "" || ![info exists gnet($nt)] || [$nt getSigType] ne "SIGNAL"} continue
        set bb [$it getBBox]
        set x [expr {([$bb xMin] + [$bb xMax]) / 2}]; set y [expr {([$bb yMin] + [$bb yMax]) / 2}]
        set bt [odb::dbBTerm_create $nt qb6_manchor_[incr nm]]
        $bt setIoType INPUT
        set bp [odb::dbBPin_create $bt]
        odb::dbBox_create $bp $lay $x $y [expr {$x + 100}] [expr {$y + 100}]
        $bp setPlacementStatus FIRM
    }
    lappend kill $i
}
set na [expr {$na + $nm}]
foreach i $kill { odb::dbInst_destroy $i }
set nF [expr {[llength $kill] - [llength $mac]}]
# rows: only the row segments inside the group's rectangles are kept (so gpl's core = the group's bounding box;
# non-row parts of it, e.g. the macros or an L-shape's notch, become gpl dummies).  A first version with
# FIRM seed cells + rectangle blockages failed GPL-0301 / 0302 (whitespace counted negative), a second with
# row-segment blockages over the whole die diverged (GPL-0307) / stalled at overflow 0.99 after 250 iterations.
set free 0.0; set nb 0; set newrows {}
foreach rw [$blk getRows] {
    set rb [$rw getBBox]; set sp [$rw getSpacing]; set site [$rw getSite]; set o [$rw getOrient]
    lassign [$rw getOrigin] ox oy
    set ym [expr {([$rb yMin] + [$rb yMax]) / 2}]
    foreach r $R($G) {
        lassign $r a b c d
        if {$ym < $b || $ym >= $d} continue
        set x1 [expr {max($a, [$rb xMin])}]; set x2 [expr {min($c, [$rb xMax])}]
        set x1 [expr {$ox + int(ceil(($x1 - $ox) / double($sp))) * $sp}]
        set ns [expr {int(($x2 - $x1) / $sp)}]
        if {$ns <= 0} continue
        lappend newrows [list $site $x1 $oy $o $ns $sp]
        set free [expr {$free + double($ns) * $sp * ([$rb yMax] - [$rb yMin])}]
    }
}
foreach rw [$blk getRows] { odb::dbRow_destroy $rw }
foreach nr $newrows {
    lassign $nr site x y o ns sp
    odb::dbRow_create $blk qb6_row_[incr nb] $site $x $y $o HORIZONTAL $ns $sp
}
set dens [expr {min(0.95, max([expr {[info exists ::env(QB_GDENS)] ? $::env(QB_GDENS) : 0.65}], 1.08 * $aM / $free))}]
puts [format "GRP %s: %d cells (+%d no group) movable %.3f mm2, rows in region %.3f mm2 (util %.3f), %d other cells removed, %d anchors, %d rows, density %.3f" \
    $G $nG $nX [expr {$aM / $u / $u / 1e6}] [expr {$free / $u / $u / 1e6}] [expr {$aM / $free}] $nF $na $nb $dens]
set t0 [clock seconds]
global_placement -density $dens -pad_left 0 -pad_right 0 {*}[expr {[info exists ::env(QB_GGPL)] ? $::env(QB_GGPL) : ""}]
# QB_GDPL 1: legalise the group inside its own rows (clipped to the rectangles: no other cells, no macros), so the
# chip's detailed placement only moves repair buffers / resized cells (r6b_a / b: > 30 min diamond search)
if {[expr {[info exists ::env(QB_GDPL)] ? $::env(QB_GDPL) : 0}]} {
    set t1 [clock seconds]
    if {[catch {detailed_placement} e]} { puts "GRP $G detailed placement failed: $e" }
    puts [format "GRP %s detailed placement %d s" $G [expr {[clock seconds] - $t1}]]
}
set ptag [expr {[info exists ::env(QB_POS_TAG)] ? $::env(QB_POS_TAG) : ""}]
set nin 0; set nout 0; set dmax 0
set fo [open $::OUT/grp_$G$ptag.pos w]
foreach i [$blk getInsts] {
    set n [$i getName]
    if {![info exists grp($n)] || $grp($n) ne $G} continue
    lassign [$i getLocation] x y
    set bb [$i getBBox]
    if {[inrect $R($G) [expr {([$bb xMin] + [$bb xMax]) / 2}] [expr {([$bb yMin] + [$bb yMax]) / 2}]]} { incr nin } else { incr nout }
    puts $fo "$n $x $y [$i getOrient]"
}
close $fo
puts [format "GRP_DONE %s gpl %d s, cells in region %d, outside %d" $G [expr {[clock seconds] - $t0}] $nin $nout]
exit
