# R43 probe: full min paths to R43_TO pins (db R43_DB [grt], placement parasitics, libs from QB11_ABS).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load [qc_env R43_DB grt]
estimate_parasitics -placement
foreach p [qc_env R43_TO ""] { report_checks -path_delay min -to $p -format full_clock_expanded -fields {input_pins} -digits 3 }
