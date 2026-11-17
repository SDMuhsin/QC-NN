# R19: band statistics (band.tcl qb19_stats) of a checkpoint: QB_DB [cts_rt] of run QC_PNR_OUT (read only) -> stdout / summary.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::QB19_DIR [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r19]
source $::QB19_DIR/band.tcl
read_db $::OUT/db/[qc_env QB_DB cts_rt].odb
set _u [[ord::get_db_tech] getDbUnitsPerMicron]
foreach b [qb19_bands] { puts "R19_BAND [lmap v $b {expr {$v / double($_u)}}]" }
qb19_stats [qc_env QB_DB cts_rt]
exit
