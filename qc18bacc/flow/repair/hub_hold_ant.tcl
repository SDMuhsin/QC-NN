# Hub QB37_HPOST_TCL hook of repair/hold_eco.tcl (blocks/hub/run.sh hold, HUB_HOLD_ANT set): antenna repair (3 iterations)
# after the global route, before fillers and detailed route, as flow pnr/or/route.tcl does it (results/r38.md: hub 3 antd29
# / 6 Calibre M8 nets).  R40 QB38_ANT_MARGIN <percent>: repair against a tightened ratio (-ratio_margin), headroom for the
# GRT -> DRT wire-length change (r38_hub_rr: 3 M8 nets at 1.04-1.27x the LEF limit after DRT); empty = no margin (R38)
set _am {}; if {[qc_env QB38_ANT_MARGIN ""] ne ""} { set _am [list -ratio_margin $::env(QB38_ANT_MARGIN)] }
repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations 3 {*}$_am
puts "R38_HPOST repair_antennas done (margin [qc_env QB38_ANT_MARGIN 0])"
