# qc_dump_conn <file>: connectivity facts def2spef.py needs and DEF does not carry in a handy form.
#   U <dbu_per_um>
#   L <layer> <ROUTING|CUT> <index>                      layer stack order
#   V <via> <bottom> <cut> <top> <ncuts>                 tech + block (generated) vias
#   I <net> <inst> <pin> <dir> <x> <y> <layer> <cell>    instance pin access point (pin bbox centre, lowest pin layer)
#   B <net> <port> <dir> <x> <y> <layer>                 top-level port
proc qc_dump_conn {file} {
    set f [open $file w]
    set tech [ord::get_db_tech]
    set block [ord::get_db_block]
    puts $f "U [$tech getDbUnitsPerMicron]"
    foreach l [$tech getLayers] {
        if {[$l getType] in {ROUTING CUT}} { puts $f "L [$l getName] [$l getType] [$l getNumber]" }
    }
    foreach v [concat [$tech getVias] [$block getVias]] {
        set bot ""; set top ""; set cut ""; set n 0
        foreach bx [$v getBoxes] {
            set l [$bx getTechLayer]
            if {$l eq "NULL"} { continue }
            if {[$l getType] eq "CUT"} { set cut [$l getName]; incr n }
        }
        catch { set bot [[$v getBottomLayer] getName]; set top [[$v getTopLayer] getName] }
        if {$cut ne ""} { puts $f "V [$v getName] $bot $cut $top $n" }
    }
    foreach net [$block getNets] {
        if {[$net getSigType] in {POWER GROUND}} { continue }
        set nn [$net getName]
        foreach it [$net getITerms] {
            set inst [$it getInst]
            set mt [$it getMTerm]
            set bl 1e9; set ln NA
            foreach mp [$mt getMPins] {
                foreach bx [$mp getGeometry] {
                    set l [$bx getTechLayer]
                    if {$l ne "NULL" && [$l getType] eq "ROUTING" && [$l getNumber] < $bl} {
                        set bl [$l getNumber]; set ln [$l getName]
                    }
                }
            }
            set bb [$it getBBox]
            set best [list [expr {([$bb xMin] + [$bb xMax]) / 2}] [expr {([$bb yMin] + [$bb yMax]) / 2}] $ln]
            set d [expr {[$it isOutputSignal] ? "O" : ([$it isInputSignal] ? "I" : "B")}]
            puts $f "I $nn [$inst getName] [$mt getName] $d [join $best { }] [[$inst getMaster] getName]"
        }
        foreach bt [$net getBTerms] {
            set d [string map {INPUT I OUTPUT O INOUT B} [$bt getIoType]]
            set xy {0 0}; set ln NA
            foreach bp [$bt getBPins] {
                foreach bx [$bp getBoxes] {
                    set xy [list [expr {([$bx xMin] + [$bx xMax]) / 2}] [expr {([$bx yMin] + [$bx yMax]) / 2}]]
                    set ln [[$bx getTechLayer] getName]
                }
            }
            puts $f "B $nn [$bt getName] $d [join $xy { }] $ln"
        }
    }
    close $f
}
