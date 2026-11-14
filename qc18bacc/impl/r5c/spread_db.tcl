# PE-row spread (spread.tcl) of a saved P&R database:  openroad -exit spread_db.tcl  with env QB5C_DB = <odb>, QB5C_DIR = this directory
# (LEF / libraries come with the odb; no timing needed).
proc qc_log {m} { puts "QC_PNR $m" }
proc qc_summary {m} { puts "QC_SUMMARY $m" }
source $::env(QB5C_DIR)/spread.tcl
read_db $::env(QB5C_DB)
qb5c_spread [file rootname [file tail $::env(QB5C_DB)]]
