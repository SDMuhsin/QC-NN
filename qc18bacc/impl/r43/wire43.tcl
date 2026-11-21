# R43 probe (read_db only): nets that already carry a dbWire / global wire in db R43_DB [grt] (repair_antennas builds
# temporary dbWires and crashed in tmg_conn::loadWire on r43_a).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
read_db $::OUT/db/[qc_env R43_DB grt].odb
set n 0; set g 0; set l {}
foreach net [[ord::get_db_block] getNets] {
    if {[$net isSpecial]} continue
    if {[$net getWire] ne "NULL"} { incr n; if {[llength $l] < 20} { lappend l [$net getName] } }
    if {[$net getGlobalWire] ne "NULL"} { incr g }
}
puts "R43_WIRE nets_with_wire $n global_wire $g first: $l"
