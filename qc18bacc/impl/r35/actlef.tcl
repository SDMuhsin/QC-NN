# R35: early top-level view of the act block from its P&R floorplan (pins final at the floorplan step): write_abstract_lef
# of db/<QB35_ADB [floorplan]> -> $QB35_AOUT (pins only are used: impl/r35/actlef.py adds full M1-M7 OBS).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
read_db $::OUT/db/[qc_env QB35_ADB floorplan].odb
write_abstract_lef -bloat_factor 0 $::env(QB35_AOUT)
puts "R35_ACTLEF done"
exit
