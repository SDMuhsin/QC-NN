# R38 opt-in QB37_HPOST_TCL hook for hold35.tcl (via hold38.sh QB38_HPOST): antenna repair after the global route, before
# fillers and detailed route, exactly as flow pnr/or/route.tcl does it (results/r38.md: hub 3 antd29 / 6 Calibre M8 nets).
repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations [qc_env QB38_ANT_ITER 3]
puts "R38_HPOST repair_antennas done"
