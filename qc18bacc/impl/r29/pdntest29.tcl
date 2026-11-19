# R29: stand-alone test of pdn29.tcl on a run db (no save unless R29_PDN_SAVE): counts before / after.
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
read_db $::OUT/db/[qc_env R29_DB grt].odb
source $::env(R29_HERE)/pdn29.tcl
if {[qc_env R29_PDN_SAVE ""] ne ""} { write_db [qc_env R29_PDN_SAVE ""] }
exit
