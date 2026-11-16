# R12: placement dump of a checkpoint (QB_DB, default grt_pl3) for q1.py / q2.py (results/r12.md):
#   M <master> <area um2>            every master of the loaded libs
#   I <inst> <master> <cx> <cy>      every placed instance (centre, um)
#   P <port> <x> <y>                 block ports
#   R <x0> <y0> <x1> <y1>            placement rows (site area)
#   B <x0> <y0> <x1> <y1> <maxdens>  placement blockages
# -> $QC_PNR_OUT/rpt/r12_dump.txt
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env QB_DB grt_pl3].odb
set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
set f [open [qc_env QB12_OUT $::OUT/rpt/r12_dump.txt] w]
foreach lib [[ord::get_db] getLibs] {
    foreach m [$lib getMasters] { puts $f [format "M %s %.4f" [$m getName] [expr {[$m getWidth] * [$m getHeight] / $u / $u}]] }
}
set blk [ord::get_db_block]
foreach i [$blk getInsts] {
    set b [$i getBBox]
    puts $f [format "I %s %s %.2f %.2f" [$i getName] [[$i getMaster] getName] [expr {([$b xMin] + [$b xMax]) / 2.0 / $u}] [expr {([$b yMin] + [$b yMax]) / 2.0 / $u}]]
}
foreach bt [$blk getBTerms] {
    set bb [$bt getBBox]
    puts $f [format "P %s %.2f %.2f" [$bt getName] [expr {([$bb xMin] + [$bb xMax]) / 2.0 / $u}] [expr {([$bb yMin] + [$bb yMax]) / 2.0 / $u}]]
}
foreach r [$blk getRows] { set b [$r getBBox]; puts $f [format "R %.3f %.3f %.3f %.3f" [expr {[$b xMin] / $u}] [expr {[$b yMin] / $u}] [expr {[$b xMax] / $u}] [expr {[$b yMax] / $u}]] }
foreach k [$blk getBlockages] { set b [$k getBBox]; puts $f [format "B %.3f %.3f %.3f %.3f %s" [expr {[$b xMin] / $u}] [expr {[$b yMin] / $u}] [expr {[$b xMax] / $u}] [expr {[$b yMax] / $u}] [$k getMaxDensity]] }
close $f
puts "R12 dump done"
exit
