# R43: special-net (PG) shapes inside a box, by layer / via and size (read-only probe).  In a run dir via
# impl/r29/or29.sh <tag> pgbox43.tcl <log>: R43_DB [pdn], R43_BOX "x1 y1 x2 y2" um.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config

read_db $::OUT/db/[qc_env R43_DB pdn].odb
set b [ord::get_db_block]; set u [$b getDefUnits]
lassign [lmap v [qc_env R43_BOX "160 5850 340 6660"] {expr {int($v * $u)}}] X1 Y1 X2 Y2
array set pgc {}
foreach net {VDD VSS} {
    set n [$b findNet $net]
    foreach sw [$n getSWires] { foreach w [$sw getWires] {
        if {[$w xMax] <= $X1 || [$w xMin] >= $X2 || [$w yMax] <= $Y1 || [$w yMin] >= $Y2} { continue }
        if {[$w isVia]} { set v [expr {[$w getTechVia] ne "NULL" ? [$w getTechVia] : [$w getBlockVia]}]; set k "via [$v getName]" } else { set k "wire [[$w getTechLayer] getName]" }
        set k [format "%s %s %.2fx%.2f" $net $k [expr {([$w xMax]-[$w xMin])/double($u)}] [expr {([$w yMax]-[$w yMin])/double($u)}]]
        incr pgc($k)
    } }
}
foreach k [lsort [array names pgc]] { puts "R43_PG $k : $pgc($k)" }
foreach i [$b getInsts] { if {[string match *u_d?/* [$i getName]] && [[$i getMaster] isBlock]} { set bb [$i getBBox]; puts "R43_MAC [$i getName] [$i getOrient] [expr {[$bb xMin]/double($u)}] [expr {[$bb yMin]/double($u)}] [expr {[$bb xMax]/double($u)}] [expr {[$bb yMax]/double($u)}]" } }
