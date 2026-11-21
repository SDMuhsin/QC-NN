# R38 opt-in QB37_HPOST_TCL hook for hold35.tcl (via hold38.sh QB38_HPOST): antenna repair after the global route, before
# fillers and detailed route, exactly as flow pnr/or/route.tcl does it (results/r38.md: hub 3 antd29 / 6 Calibre M8 nets).
# R40 opt-in QB38_ANT_MARGIN <percent>: repair against a tightened ratio (-ratio_margin), headroom for the GRT -> DRT
# wire-length change (r38_hub_rr: 3 M8 nets at 1.04-1.27x the LEF limit after DRT); unset = as R38
set _am {}; if {[qc_env QB38_ANT_MARGIN ""] ne ""} { set _am [list -ratio_margin $::env(QB38_ANT_MARGIN)] }
repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations [qc_env QB38_ANT_ITER 3] {*}$_am
puts "R38_HPOST repair_antennas done (margin [qc_env QB38_ANT_MARGIN 0])"
