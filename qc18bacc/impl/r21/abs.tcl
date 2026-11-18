# R21 abstracts of the routed hub (run.sh abs, in the P&R run dir), as impl/r9a/abs.tcl without the act-pin check:
# write_abstract_lef -bloat_factor 0 -> $QB21_ABS_OUT/qb_hub.lef (die printed as R21_ABS_DIE for impl/r9a/lef_size.py),
# pin count per die edge.  Antenna check is run separately (run.sh ant).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_read_liberty
read_db $::OUT/db/[qc_env QB21_DB route].odb
set blk [ord::get_db_block]; set die [$blk getDieArea]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
puts [format "QB9_DIE %.3f %.3f" [expr {[$die dx] / double($u)}] [expr {[$die dy] / double($u)}]]
puts [format "R21_ABS_DIE %.3f %.3f" [expr {[$die dx] / double($u)}] [expr {[$die dy] / double($u)}]]
write_abstract_lef -bloat_factor 0 $::env(QB21_ABS_OUT)/qb_hub.lef
set ns 0; set nn 0; set nw 0; set ne 0
foreach bt [$blk getBTerms] {
    set bp [lindex [$bt getBPins] 0]; if {$bp eq ""} { continue }
    set bx [lindex [$bp getBoxes] 0]
    if {[$bx yMin] == [$die yMin]} { incr ns } elseif {[$bx yMax] == [$die yMax]} { incr nn } elseif {[$bx xMax] == [$die xMax]} { incr ne } else { incr nw }
}
puts "R21_ABS pins south $ns north $nn east $ne west $nw lef $::env(QB21_ABS_OUT)/qb_hub.lef"
exit
