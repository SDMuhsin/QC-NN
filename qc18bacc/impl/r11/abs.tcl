# R11 (impl/r11/run.sh hubfp): abstract LEF of a floorplanned block (pins + full obstruction) from QB_DB -> QB_LEF.
# Used for the hub (no routed hub yet): pins as placed by the R10b pin plan, die = the hub floorplan die.
read_db $::env(QB_DB)
write_abstract_lef -bloat_factor 0 $::env(QB_LEF)
set u [[ord::get_db_tech] getDbUnitsPerMicron]
set d [[ord::get_db_block] getDieArea]
puts "R11_ABS die [expr {[$d dx] / double($u)}] x [expr {[$d dy] / double($u)}] pins [llength [[ord::get_db_block] getBTerms]]"
