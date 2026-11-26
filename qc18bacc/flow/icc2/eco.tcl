# Sign-off ECO of the routed block (R56, results/r56.md): the PrimeTime change list of signoff/pt/drv_eco.tcl
# (<run>/out/eco/pt_eco.tcl, icc2tcl: size_cell / insert_buffer / add_buffer_on_route, sourced) on the block label PT
# analysed, QB_ECO_FROM (route, or the label of the round before: <run>/out/label.txt) -> label QB_ECO_TO (eco, eco2, ...:
# one label per round of the ECO loop, common/block.sh, R92; reports and summary lines carry it).  New cells without a PT
# location are placed (place_eco_cells), then every changed cell is legalised on free sites (filler / decap cells under
# it removed), ECO-routed (route_eco, routing options of route.tcl), the emptied sites refilled (decap then FILL, as
# route.tcl), route closure + hard gate (common.tcl qb_route_close, R92: check_routes / check_lvs -check_child_cells all 0
# or the step fails).  No optimisation here: the change list is the whole ECO.
# ECO routing touches only what PT changed (R73, results/r73.md): PT's DMSA predicts every net outside its change list
# unchanged, so route_eco must not rip those up.  Two router settings did, every round, anywhere in the block:
# * route.detail.eco_route_use_soft_spacing_for_timing_optimization (on with route.detail.timing_driven): route_eco's
#   "timing optimization in DR" puts soft spacing rules around the nets ICC2 finds critical at the P&R SDC (r73 round 2,
#   3 nets to route: 1385 soft DRCs, 1317 violations) and reroutes their neighbours.  r72 + r73 [M]: the same 13 nets
#   (act / act_o feedthroughs, clock nets) within 20 um of g_col_0 u_dec net DP_OP_223_315_5193_n289 moved in round 2,
#   ~395 um from the nearest ECO cell, and its ss transition went 0.500 -> 0.50155 (r72) / 0.52 ns (r73) with its own
#   route unchanged; the same reroutes moved the act_o noise victims of round 1 to other bits.  Off here (route_eco only).
# * -reroute any_nets (default): on the unchanged eco label route_eco changed 15 nets; modified_nets_first_then_others 0.
#   modified_nets_only left 81 DRC violations (r73 round-1 change list) [M], so others may still move for real DRCs.
source [file dirname [info script]]/common.tcl
set lab [qc_env QB_ECO_TO eco]
qb_open [qc_env QB_ECO_FROM route] $lab
qb_route_setup
set chg $::R/out/eco/pt_eco.tcl
set n0 [sizeof_collection [get_flat_cells]]
source $chg
set fill {}; foreach c [concat $::QC_PNR_DCAP $::QC_PNR_FILL] { lappend fill */$c }
set fill [get_lib_cells $fill]
set up [get_flat_cells -quiet -filter "physical_status==unplaced"]
qb_line "$lab [file tail $chg]: cells $n0 -> [sizeof_collection [get_flat_cells]], unplaced [sizeof_collection $up]"
# change-list gate (R89 / R91): every object the change list names exists and every new cell = PT's record (qb_eco_names);
# before placement / routing
lassign [qb_eco_names $chg] nl nb
qb_line $nl
if {$nb} { error "$lab: $nb objects of [file tail $chg] missing or mismatched in the block (rpt/eco_names.rpt)" }
if {[sizeof_collection $up]} { place_eco_cells -cells $up -remove_filler_references $fill }
place_eco_cells -eco_changed_cells -legalize_only -remove_filler_references $fill
# Hard gate (R81, PI decision; the shared proc common.tcl qb_legality since R92): any legality violation, cell overlap,
# unplaced cell or unparsed report after place_eco_cells fails the eco step here, before route_eco.  R80 [M]: an in-place-
# upsized fixed cell overlapping a neighbour is not something route_eco or the later steps can repair (r79: 2 shorts stuck
# through DR, LVS INCORRECT, base-layer DRC); the PT ECO is physically aware only (signoff/pt/drv_eco.tcl), so a violation
# here is a bug to diagnose, not to route over.
qb_legality $lab
set_app_options -name route.detail.eco_route_use_soft_spacing_for_timing_optimization -value false
route_eco -utilize_dangling_wires true -reroute modified_nets_first_then_others
qb_fillers
qb_route_close $lab
qb_isolate_report $lab
qb_qor $lab
qb_done $lab
