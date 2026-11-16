# PRE_PLACE_TCL of impl/r9a/act.cfg (results/r9a.md): impl/r7c/gpl_incr2.tcl (DRV repair, incremental re-spread, second
# repair) plus a structured placement of the east-edge act output cells.
# R7c failure: gpl pulls the 4 608 last-stage act flops (+ DC's port buffers) onto their pins, 288 per column row in
# 80-100-um y bands on the east edge; local density there exceeds 1 and DPL fails (DPL-0036) or, with a 500-um window,
# throws cells far away and loses the repaired timing.  Here, before gpl, every act[b] output chain (port <- single-
# fanout buffers / inverters <- flop, walked back from the port) is placed legally next to its pin:
#   (the flop is taken also when it drives other logic besides the port buffer)
#   * rows sorted by distance from the pin y; a chain goes into the nearest row with room, east to west from the
#     core's east edge, then a gap of QB9_EDGE_GAP x the chain width (default 0.6: local density ~0.6, room for CTS
#     buffers / repair), at most QB9_EDGE_D um deep (default 60)
#   * FIRM (fixed for gpl / incremental gpl) during global placement; PLACED afterwards (repair may resize them, DPL
#     may nudge them)
# Report: rpt/r9a_edge.txt (chains, cells, depth used, max |dy| cell - pin).
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r7c/gpl_incr2.tcl]
proc qb9_is_buf {m} { return [regexp {^(BUFF|CKBD|INV|CKND|DEL)} [$m getName]] }
proc qb9_is_ff {m} { return [regexp {^(DF|SDF|EDF|LH|LN)} [$m getName]] }
proc qb9_chain {bt} {
    set ch {}; set net [$bt getNet]
    for {set k 0} {$k < 4 && $net ne "NULL"} {incr k} {
        set drv NULL; set nload 0
        foreach it [$net getITerms] {
            if {[$it isOutputSignal]} { set drv $it } else { incr nload }
        }
        if {$drv eq "NULL" || $nload > 0 || [llength [$net getBTerms]] != 1} { break }
        set i [$drv getInst]; set m [$i getMaster]
        lappend ch $i
        if {[qb9_is_ff $m] || ![qb9_is_buf $m]} { break }
        set net NULL
        foreach it [$i getITerms] { if {[$it isInputSignal]} { set net [$it getNet] } }
        # the buffer's input net feeds other cells too (DC's port buffer when the act flop also drives other logic):
        # take its driver only if it is the act flop, then stop
        if {$net ne "NULL" && ([llength [$net getITerms]] != 2 || [llength [$net getBTerms]] != 0)} {
            foreach it [$net getITerms] {
                if {[$it isOutputSignal] && [qb9_is_ff [[$it getInst] getMaster]]} { lappend ch [$it getInst] }
            }
            break
        }
    }
    return $ch
}
proc qb9_edge {} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set core [$blk getCoreArea]; set xr [$core xMax]
    set gap [qb_env QB9_EDGE_GAP 0.6]; set dmax [expr {round([qb_env QB9_EDGE_D 60.0] * $u)}]
    set rows {}
    foreach rw [$blk getRows] {
        lassign [$rw getOrigin] rx ry
        set sw [[$rw getSite] getWidth]; set rh [[$rw getSite] getHeight]
        lappend rows [list [expr {$ry + $rh / 2}] $ry $rx $sw [$rw getOrient] [[$rw getBBox] xMax]]
    }
    set rows [lsort -integer -index 0 $rows]; set nr [llength $rows]
    set ys {}; foreach r $rows { lappend ys [lindex $r 0] }
    array set cur {}; array set xe {}
    for {set k 0} {$k < $nr} {incr k} { set cur($k) [lindex $rows $k 5]; set xe($k) $cur($k) }
    set pins {}
    foreach bt [$blk getBTerms] {
        if {![regexp {^act\[(\d+)\]$} [$bt getName] -> b]} { continue }
        set bp [lindex [$bt getBPins] 0]; set bx [lindex [$bp getBoxes] 0]
        lappend pins [list [expr {([$bx yMin] + [$bx yMax]) / 2}] $bt]
    }
    set nch 0; set ncell 0; set nfail 0; set dymax 0; set dep 0; set nflop 0
    array set used {}
    foreach pe [lsort -integer -index 0 $pins] {
        lassign $pe py bt
        set ch [qb9_chain $bt]
        if {![llength $ch]} { incr nfail; continue }
        set cw 0; set ok 1
        foreach i $ch {
            if {[info exists used([$i getName])]} { set ok 0 }
            set cw [expr {$cw + [[$i getMaster] getWidth]}]
        }
        if {!$ok} { incr nfail; continue }
        # nearest row index by binary search, then outwards
        set lo 0; set hi [expr {$nr - 1}]
        while {$lo < $hi} { set mid [expr {($lo + $hi) / 2}]; if {[lindex $ys $mid] < $py} { set lo [expr {$mid + 1}] } else { set hi $mid } }
        set k0 $lo; set pick -1
        for {set d 0} {$d < $nr && $pick < 0} {incr d} {
            foreach k [list [expr {$k0 - $d}] [expr {$k0 + $d}]] {
                if {$k < 0 || $k >= $nr || $pick >= 0} { continue }
                if {$xe($k) - ($cur($k) - $cw) <= $dmax} { set pick $k }
            }
        }
        if {$pick < 0} { incr nfail; continue }
        lassign [lindex $rows $pick] yc ry rx sw ori
        set x $cur($pick)
        foreach i $ch {
            set w [[$i getMaster] getWidth]
            set x [expr {$rx + (($x - $w - $rx) / $sw) * $sw}]
            $i setOrient $ori
            $i setLocation $x $ry
            $i setPlacementStatus FIRM
            set used([$i getName]) 1
            if {[qb9_is_ff [$i getMaster]]} { incr nflop }
            incr ncell
        }
        set g [expr {int(ceil($gap * $cw / double($sw))) * $sw}]
        set cur($pick) [expr {$x - $g}]
        set dep [expr {max($dep, $xr - $x)}]
        set dymax [expr {max($dymax, abs($yc - $py))}]
        incr nch
    }
    set ::QB9_EDGE [array names used]
    set s [format "r9a_edge chains %d cells %d flops %d not_placed %d depth_um %.1f max_dy_um %.1f gap %.2f" \
        $nch $ncell $nflop $nfail [expr {$dep / double($u)}] [expr {$dymax / double($u)}] $gap]
    set f [open $::OUT/rpt/r9a_edge.txt w]; puts $f $s; close $f
    qc_summary $s
}
proc qb9_status {st} {
    set blk [ord::get_db_block]
    foreach n $::QB9_EDGE { set i [$blk findInst $n]; if {$i ne "NULL"} { $i setPlacementStatus $st } }
}
if {[info commands qb9_gpl_orig] eq ""} {
    rename global_placement qb9_gpl_orig
    proc global_placement {args} {
        file mkdir $::OUT/rpt
        if {![info exists ::QB9_EDGE]} { if {[qb_env QB9_EDGE_ON 1]} { qb9_edge } else { set ::QB9_EDGE {} } }
        qb9_status FIRM
        qb9_gpl_orig {*}$args
        qb9_status PLACED
    }
}
