# Placement + pre-CTS optimisation: MCMM place_opt (setup scenarios of site.tcl QC_ROLE, max transition / capacitance in every scenario), tie cells
# of site/pnr.tcl allowed, no scan DEF (the DC netlist has no stitched chains), clock nets on M3-M6 with double spacing
# (latency estimates here, the tree in cts.tcl).  Block label floorplan -> place.
source [file dirname [info script]]/common.tcl
qb_open floorplan place
set_lib_cell_purpose -include optimization [get_lib_cells [list */[lindex $::QC_PNR_TIEHI 0] */[lindex $::QC_PNR_TIELO 0]]]
set_app_options -name time.remove_clock_reconvergence_pessimism -value true
# keep the netlist's clock gates (R65 [M]): place_opt merges equivalent ICGs by default (r64: 227 DC CKLNQD1 -> 51, ~160 sinks
# each); CTS then sizes each merged gate to its ss library max_capacitance on global-route parasitics (CKLNQD8 Q 0.4707 pF)
# and the detail-routed net ends above it (0.4857 pF), where no later step can fix it: post-CTS ICC2 has no
# alternative lib cells for CKLNQD* (no function_id), so synthesize_clock_trees -postroute / route_opt clock DRC fixing
# fail every attempt, and PrimeTime does not change clock nets.
set_app_options -name place_opt.flow.merge_clock_gates -value false
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
