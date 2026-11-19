# R27 (results/r27.md) PRE_PLACE_TCL: impl/r21/place_pre.tcl unchanged, plus opt-in hooks around the place-step DRV repair:
#   QB27_MODE save    write the global placement (all inst locations / status, after repair_tie_fanout) to QB27_LOCS
#                     at entry of qc_repair_drv (i.e. right before repair_design), then repair as usual
#   QB27_MODE replay  the non-incremental global_placement call restores the QB27_LOCS placement instead of placing
#                     (same pre-repair placement for every sweep point); incremental calls run unchanged
#   QB27_BUFMIN 1     set_dont_use BUFFD1 BUFFD2 BUFFD3 (repair_design buffers BUFFD4 and above only)
#   R27_PRE lines: std-cell area / instances / signal pins at repair entry.
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r21/place_pre.tcl]
proc qb27_stats {tag} {
    set a 0.0; set n 0; set p 0
    set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
    foreach i [[ord::get_db_block] getInsts] {
        set m [$i getMaster]; if {[$m isBlock]} continue
        incr n; set a [expr {$a + [$m getWidth] * [$m getHeight] / $u / $u}]
        foreach it [$i getITerms] { set nt [$it getNet]; if {$nt ne "NULL" && [$nt getSigType] eq "SIGNAL"} { incr p } }
    }
    qc_log [format "R27_STATS %s std_um2 %.1f insts %d signal_pins %d" $tag $a $n $p]
}
if {[qb_env QB27_BUFMIN 0]} {
    set _bl {}
    foreach c {BUFFD1 BUFFD2 BUFFD3} { lappend _bl {*}[get_lib_cells -quiet */$c] }
    set_dont_use $_bl
    qc_log "R27: dont_use [llength $_bl] lib cells BUFFD1-3 (buffers >= BUFFD4 only)"
}
set _m [qb_env QB27_MODE ""]
if {$_m eq "save" && [info commands qb27_drv_in] eq ""} {
    rename qc_repair_drv qb27_drv_in
    proc qc_repair_drv {} {
        set f [open [qb_env QB27_LOCS ""] w]
        foreach i [[ord::get_db_block] getInsts] {
            if {[[$i getMaster] isBlock]} continue
            puts $f "[$i getName] [$i getLocation] [$i getOrient] [$i getPlacementStatus]"
        }
        close $f
        qb27_stats pre
        qb27_drv_in
    }
}
if {$_m eq "replay" && [info commands qb27_gpl] eq ""} {
    rename global_placement qb27_gpl
    proc global_placement {args} {
        if {"-incremental" in $args} { return [qb27_gpl {*}$args] }
        set blk [ord::get_db_block]; set f [open [qb_env QB27_LOCS ""]]; set n 0; set miss 0
        while {[gets $f l] >= 0} {
            lassign $l nm x y o st
            set i [$blk findInst $nm]; if {$i eq "NULL"} { incr miss; continue }
            $i setOrient $o; $i setLocation $x $y; $i setPlacementStatus $st; incr n
        }
        close $f
        qc_log "R27: replayed global placement of $n instances ($miss names not present: repair_tie_fanout cells)"
    }
    rename qc_repair_drv qb27_drv_in
    proc qc_repair_drv {} { qb27_stats pre; qb27_drv_in }
}
# QB27_TWO <um> (opt-in): every base DRV repair (qb_drv_orig) runs in two stages: (A) signal nets with pin-bbox HPWL
# < QB27_TWO um are dont_touch, so only the long violators are buffered / resized; (B) the violators are re-collected
# with the repaired input slews and the rest are repaired.  Tests whether short-net resizing is cascaded input slew.
if {[qb_env QB27_TWO ""] ne "" && [info commands qb27_base] eq ""} {
    rename qb_drv_orig qb27_base
    proc qb_drv_orig {} {
        set lim [expr {[qb_env QB27_TWO 200] * [[ord::get_db_tech] getDbUnitsPerMicron]}]; set dt {}
        foreach n [[ord::get_db_block] getNets] {
            if {[$n getSigType] ne "SIGNAL" || [$n isDoNotTouch]} continue
            set xa 1e12; set xb -1e12; set ya 1e12; set yb -1e12
            foreach it [$n getITerms] { set b [[$it getInst] getBBox]; set x [$b xMin]; set y [$b yMin]
                if {$x < $xa} { set xa $x }; if {$x > $xb} { set xb $x }; if {$y < $ya} { set ya $y }; if {$y > $yb} { set yb $y } }
            foreach bt [$n getBTerms] { set b [$bt getBBox]; set x [$b xMin]; set y [$b yMin]
                if {$x < $xa} { set xa $x }; if {$x > $xb} { set xb $x }; if {$y < $ya} { set ya $y }; if {$y > $yb} { set yb $y } }
            if {$xb - $xa + $yb - $ya < $lim} { $n setDoNotTouch 1; lappend dt $n }
        }
        qc_log "R27_TWO stage A: [llength $dt] short nets (< [qb_env QB27_TWO 200] um) dont_touch"
        qb27_base
        foreach n $dt { $n setDoNotTouch 0 }
        estimate_parasitics -placement
        qc_log "R27_TWO stage B"
        qb27_base
    }
}
