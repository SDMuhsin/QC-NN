source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set _f [open $::OUT/config.tcl]; set _t [read $_f]; close $_f
eval [string map {r31_snap/ r31_snap4/} $_t]
qc_config
source /tmp/ckp908/qc18bacc/r32/m32.tcl
qc_read_liberty
foreach db [qc_env R32_DBS {pdn place cts_rt finish}] {
  read_db $::OUT/db/$db.odb
  r32_metrics $db
  [ord::get_db] clear
}
exit
