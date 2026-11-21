# R36 (results/r36.md): dump the top's special-net (PDN) shapes on R36_LAYERS [M6 M7 M8 M9 VIA6 VIA7 VIA8] and the
# hard-block placements of a db (R36_DB [pdn]) to rpt/r36_pg.txt for impl/r36/pgovl.py (overlap vs final block LEFs).
# Run with impl/r29/or29.sh <tag> <this> <log>.  Lines: "S <net> <layer> x0 y0 x1 y1" (um), "I <inst> <master> <orient> x y".
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/[qc_env R36_DB pdn].odb
set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
set keep [qc_env R36_LAYERS {M6 M7 M8 M9 VIA6 VIA7 VIA8}]
set f [open $::OUT/rpt/r36_pg.txt w]
set n 0
proc wbox {f net b u keep} {
    set l [$b getTechLayer]; if {$l eq "NULL"} { return 0 }
    set ln [$l getName]; if {$ln ni $keep} { return 0 }
    puts $f [format "S %s %s %.3f %.3f %.3f %.3f" $net $ln [expr {[$b xMin]/double($u)}] [expr {[$b yMin]/double($u)}] [expr {[$b xMax]/double($u)}] [expr {[$b yMax]/double($u)}]]
    return 1
}
foreach net [$blk getNets] {
    if {![$net isSpecial]} { continue }
    set nn [$net getName]
    foreach sw [$net getSWires] {
        foreach w [$sw getWires] {
            if {[$w isVia]} {
                set boxes {}
                if {[$w getTechVia] ne "NULL"} { set boxes [[$w getTechVia] getBoxes] } elseif {[$w getBlockVia] ne "NULL"} { set boxes [[$w getBlockVia] getBoxes] }
                if {[catch { set xy [$w getViaXY]; set cx [lindex $xy 0]; set cy [lindex $xy 1] }]} {
                    set cx [expr {([$w xMin] + [$w xMax]) / 2}]; set cy [expr {([$w yMin] + [$w yMax]) / 2}] }
                foreach b $boxes {
                    set l [$b getTechLayer]; if {$l eq "NULL"} { continue }
                    set ln [$l getName]; if {$ln ni $keep} { continue }
                    # via boxes are relative to the via origin = the wire's centre point
                    puts $f [format "S %s %s %.3f %.3f %.3f %.3f" $nn $ln [expr {($cx+[$b xMin])/double($u)}] [expr {($cy+[$b yMin])/double($u)}] [expr {($cx+[$b xMax])/double($u)}] [expr {($cy+[$b yMax])/double($u)}]]
                    incr n
                }
            } else { incr n [wbox $f $nn $w $u $keep] }
        }
    }
}
foreach i [$blk getInsts] {
    set m [$i getMaster]
    if {![$m isBlock]} { continue }
    set loc [$i getLocation]
    set bb [$i getBBox]
    puts $f [format "I %s %s %s %.3f %.3f %.3f %.3f %.3f %.3f" [$i getName] [$m getName] [$i getOrient] [expr {[lindex $loc 0]/double($u)}] [expr {[lindex $loc 1]/double($u)}] \
        [expr {[$bb xMin]/double($u)}] [expr {[$bb yMin]/double($u)}] [expr {[$bb xMax]/double($u)}] [expr {[$bb yMax]/double($u)}]]
}
close $f
puts "R36_PGDUMP shapes $n -> $::OUT/rpt/r36_pg.txt"
exit
