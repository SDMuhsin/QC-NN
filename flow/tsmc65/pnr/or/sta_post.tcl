# Post-route timing in OpenROAD with the def2spef.py SPEF of each corner (driven by pnr/run_pnr.sh).
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load finish
set top [p TOP]
foreach c $::QC_CORNERS { read_spef -corner $c $::OUT/out/${top}_$c.spef }
qc_report post_route
qc_to $::OUT/rpt/post_route.annotation.rpt { report_parasitic_annotation -report_unannotated }
foreach l [qc_timing_lines post_route] { qc_summary $l }
exit
