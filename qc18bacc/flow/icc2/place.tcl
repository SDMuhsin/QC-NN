# Placement + pre-CTS optimisation: MCMM place_opt (setup scenarios of site.tcl QC_ROLE, max transition / capacitance in every scenario), tie cells
# of site/pnr.tcl allowed, no scan DEF (the DC netlist has no stitched chains), clock nets on M3-M6 with double spacing
# (latency estimates here, the tree in cts.tcl).  Block label floorplan -> place.
source [file dirname [info script]]/common.tcl
qb_open floorplan place
set_lib_cell_purpose -include optimization [get_lib_cells [list */[lindex $::QC_PNR_TIEHI 0] */[lindex $::QC_PNR_TIELO 0]]]
set_app_options -name time.remove_clock_reconvergence_pessimism -value true
# keep the netlist's clock gates (R65 [M]): place_opt merges equivalent ICGs by default (r64: 227 DC CKLNQD1 -> 51, ~160 sinks
# each); CTS sizes each gate to zero slack on its estimate, and r64's merged gates ended over their ss limit after clock
# routing (cts label: 4 gates, 0.4857 / 0.4829 / 0.4736 / 0.4723 vs CKLNQD8 Q 0.4707 pF; 2 at sign-off).  Still needed
# (R75 [M]): ICC2's post-route clock DRC fixing never resizes a clock gate (cts.tcl), so every gate that routing pushes
# over is left to the sign-off ECO's clock-network buffers; the 32-sink DC gates keep that to 1 gate, 0.55 fF (r74, r75
# cts labels) where the merged 160-sink gates had 4, up to 15 fF.  Cost: 176 more ICGs, +1138 um2 clock cell area (0.10 %
# of the core, R65).
set_app_options -name place_opt.flow.merge_clock_gates -value false
set_app_options -name place.coarse.continue_on_missing_scandef -value true
create_routing_rule qb_clk -multiplier_spacing 2
set_clock_routing_rules -rules qb_clk -min_routing_layer M3 -max_routing_layer M6
# netlist-targeted hold-cell reservation (R87; common.tcl qb_hold_reserve, blocks with P(HOLD_RESERVE)): soft keepouts
# on the DC netlist before place_opt's coarse placement
qb_hold_reserve
# input-port isolation (R88; common.tcl qb_isolate_ports, blocks with P(ISOLATE)): ICC2 set_isolate_ports, the buffers
# inserted by place_opt's initial_drc stage, then pulled to their port terminals (qb_isolate_magnet) before optimisation
if {[qb_isolate_ports]} {
    place_opt -to initial_drc
    qb_isolate_magnet
    place_opt -from initial_opto
} else { place_opt }
qb_isolate_report place
redirect -variable lg { check_legality }
qb_line "place check_legality: [regsub -all {\s+} [join [lrange [regexp -all -inline -line {^.*(?:[Vv]iolat|succeeded|failed).*$} $lg] 0 2] { | }] { }]"
redirect $::R/rpt/place_congestion.rpt { report_congestion -rerun_global_router }
qb_line "place [regsub -all {\s+} [lindex [regexp -inline -line {^Both Dirs.*$} [exec cat $::R/rpt/place_congestion.rpt]] 0] { }]"
qb_qor place
qb_done place
