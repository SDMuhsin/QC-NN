# R22 (results/r22.md): S-macro net spans of a placed hub checkpoint (QB_DB [place]) for sq22.py - which S macro
# nets cross the die middle (band H bisection, budget item 2).  One line per signal net on an S macro pin:
#   S <macro inst> <macro cx> <macro cy> <pin dir I|O> <pin> <net bbox xmin> <xmax> <ymin> <ymax> <fanout pins>
# (bbox over the loads / drivers other than the macro: instance centres and ports, through BUFF / CKBD / INV / CKND / DEL
# repair cells on the load side, um; the macro pin itself is excluded, the macro centre is printed).  -> $QB22_OUT
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env QB_DB place].odb
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set f [open $::env(QB22_OUT) w]
foreach i [[ord::get_db_block] getInsts] {
    if {[[$i getMaster] getName] ne "qb_s_256x128m1"} { continue }
    set b [$i getBBox]
    set cx [expr {([$b xMin] + [$b xMax]) / 2.0 / $u}]; set cy [expr {([$b yMin] + [$b yMax]) / 2.0 / $u}]
    foreach it [$i getITerms] {
        set n [$it getNet]
        if {$n eq "NULL" || [$n getSigType] ne "SIGNAL"} { continue }
        # follow repair buffers / inverters to the real loads (the class of a buffered Q is its whole buffer tree)
        set x0 1e9; set x1 -1e9; set y0 1e9; set y1 -1e9; set k 0; set todo [list $n]; set seen [dict create]
        while {[llength $todo]} {
            set m [lindex $todo 0]; set todo [lrange $todo 1 end]
            set mk [$m getName]; if {[dict exists $seen $mk]} { continue }; dict set seen $mk 1
            foreach jt [$m getITerms] {
                set ji [$jt getInst]
                if {$ji eq $i} { continue }
                if {[$jt isInputSignal] && [regexp {^(BUFF|CKBD|INV|CKND|DEL)} [[$ji getMaster] getName]]} {
                    foreach ot [$ji getITerms] { if {[$ot isOutputSignal] && [$ot getNet] ne "NULL"} { lappend todo [$ot getNet] } }
                    continue
                }
                set jb [$ji getBBox]
                set x [expr {([$jb xMin] + [$jb xMax]) / 2.0 / $u}]; set y [expr {([$jb yMin] + [$jb yMax]) / 2.0 / $u}]
                if {$x < $x0} { set x0 $x }; if {$x > $x1} { set x1 $x }; if {$y < $y0} { set y0 $y }; if {$y > $y1} { set y1 $y }
                incr k
            }
            foreach bt [$m getBTerms] {
                set bb [$bt getBBox]
                set x [expr {([$bb xMin] + [$bb xMax]) / 2.0 / $u}]; set y [expr {([$bb yMin] + [$bb yMax]) / 2.0 / $u}]
                if {$x < $x0} { set x0 $x }; if {$x > $x1} { set x1 $x }; if {$y < $y0} { set y0 $y }; if {$y > $y1} { set y1 $y }
                incr k
            }
        }
        puts $f [format "S %s %.1f %.1f %s %s %.1f %.1f %.1f %.1f %d" [$i getName] $cx $cy [expr {[$it isOutputSignal] ? "O" : "I"}] \
            [[$it getMTerm] getName] $x0 $x1 $y0 $y1 $k]
    }
}
close $f
puts "R22_SQ done"
exit
