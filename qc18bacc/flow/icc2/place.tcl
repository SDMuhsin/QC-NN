# Placement + pre-CTS optimisation: MCMM place_opt (ss setup, max transition / capacitance in every scenario), tie cells
# of site/pnr.tcl allowed, no scan DEF (the DC netlist has no stitched chains), clock nets on M3-M6 with double spacing
# (latency estimates here, the tree in cts.tcl).  Block label floorplan -> place.
source [file dirname [info script]]/common.tcl
qb_open floorplan place
set_lib_cell_purpose -include optimization [get_lib_cells [list */[lindex $::QC_PNR_TIEHI 0] */[lindex $::QC_PNR_TIELO 0]]]
set_app_options -name time.remove_clock_reconvergence_pessimism -value true
set_app_options -name place.coarse.continue_on_missing_scandef -value true
create_routing_rule qb_clk -multiplier_spacing 2
set_clock_routing_rules -rules qb_clk -min_routing_layer M3 -max_routing_layer M6
place_opt
redirect -variable lg { check_legality }
qb_line "place check_legality: [regsub -all {\s+} [join [lrange [regexp -all -inline -line {^.*(?:[Vv]iolat|succeeded|failed).*$} $lg] 0 2] { | }] { }]"
redirect $::R/rpt/place_congestion.rpt { report_congestion -rerun_global_router }
qb_line "place [regsub -all {\s+} [lindex [regexp -inline -line {^Both Dirs.*$} [exec cat $::R/rpt/place_congestion.rpt]] 0] { }]"
qb_qor place
qb_done place
