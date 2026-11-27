# Sign-off ECO of the routed block (R56, results/r56.md): the PrimeTime change list of signoff/pt/drv_eco.tcl
# (<run>/out/eco/pt_eco.tcl, icc2tcl: size_cell / insert_buffer / add_buffer_on_route, sourced) on the block label PT
# analysed, QB_ECO_FROM (route, or the label of the round before: <run>/out/label.txt) -> label QB_ECO_TO (eco, eco2, ...:
# one label per round of the ECO loop, common/block.sh, R92; reports and summary lines carry it).  New cells without a PT
# location are placed (place_eco_cells), then every changed cell is legalised on free sites (filler / decap cells under
# it removed), ECO-routed (route_eco, routing options of route.tcl), the emptied sites refilled (decap then FILL, as
# route.tcl), hard route gate (common.tcl qb_route_close with 0 closure passes, R92: check_routes / check_lvs
# -check_child_cells all 0 or the step fails; no closure pass inside a round until it is local, PI decision, [M] there).
# No optimisation here: the change list is the whole ECO.
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
# route_eco -nets = the nets of the changed cells (R105, common.tcl qb_eco_nets).  size_cell swaps the master in place,
# connectivity unchanged, so ICC2 marks no net modified ("There are no modified nets in the design") and route_eco
# rerouted nothing; where the larger master's M1 pins land on the pin-access wiring of its own nets the shorts stay.  [M]
# rgr rg83c65a6a round 1 (1 of 54 eco rounds over 40 rgr runs): HFSINV_586_179 INVD4 -> INVD6, u_lane/U1130 INVD1 -> CKND2,
# 3 shorts + 4 DRCs right after size_cell, before legalisation; the gate below failed.  On a copy: route_eco -nets <their
# nets> rerouted exactly 4 nets (n882, n884, HFSNET_76, p1[9]) to 0 / 0; a closure pass (route_detail -incremental) also
# cleared it but rerouted ~91 nets PT predicted unchanged (R73).  -nets also bounds route_eco's open-net connection, so it
# holds the nets of new cells too (the gate fails on any open left).
source [file dirname [info script]]/common.tcl
set lab [qc_env QB_ECO_TO eco]
qb_open [qc_env QB_ECO_FROM route] $lab
qb_route_setup
set chg $::R/out/eco/pt_eco.tcl
set n0 [sizeof_collection [get_flat_cells]]
# sourced as resolved (common.tcl qb_eco_route_resolve): PT's layer-0 add_buffer_on_route buffers on their routes (R95),
# each buffer's point where ICC2 gives it exactly PT's loads (R101), each buffer left on that point (R108: PT's
# set_cell_location of it not applied); where the buffers are placed, for the report after legalisation
source [qb_eco_route_resolve $chg $::R/out/eco/$lab/pt_eco_resolved.tcl]
set abor_placed [qb_eco_abor_where]
set fill {}; foreach c [concat $::QC_PNR_DCAP $::QC_PNR_FILL] { lappend fill */$c }
set fill [get_lib_cells $fill]
set up [get_flat_cells -quiet -filter "physical_status==unplaced"]
qb_line "$lab [file tail $chg]: cells $n0 -> [sizeof_collection [get_flat_cells]], unplaced [sizeof_collection $up]"
# change-list gate (R89 / R91): every object the change list names exists and every new cell = PT's record (qb_eco_names);
# before placement / routing
lassign [qb_eco_names $chg] nl nb
qb_line "$lab $nl"   ;# (the label first: signoff/verdict.py gates the latest line of the label of out/)
if {$nb} { error "$lab: $nb objects of [file tail $chg] missing or mismatched in the block (rpt/eco_names.rpt)" }
if {[sizeof_collection $up]} { place_eco_cells -cells $up -remove_filler_references $fill }
place_eco_cells -eco_changed_cells -legalize_only -remove_filler_references $fill
# Hard gate (R81, PI decision; the shared proc common.tcl qb_legality since R92): any legality violation, cell overlap,
# unplaced cell or unparsed report after place_eco_cells fails the eco step here, before route_eco.  R80 [M]: an in-place-
# upsized fixed cell overlapping a neighbour is not something route_eco or the later steps can repair (r79: 2 shorts stuck
# through DR, LVS INCORRECT, base-layer DRC); the PT ECO is physically aware only (signoff/pt/drv_eco.tcl), so a violation
# here is a bug to diagnose, not to route over.
qb_legality $lab
qb_eco_abor_report $lab $abor_placed
set_app_options -name route.detail.eco_route_use_soft_spacing_for_timing_optimization -value false
lassign [qb_eco_nets $chg] nc rn
qb_line "$lab route_eco nets [sizeof_collection $rn] (pins of $nc changed cells)"
route_eco -nets $rn -utilize_dangling_wires true -reroute modified_nets_first_then_others
qb_fillers
qb_route_close $lab 0
qb_isolate_report $lab
qb_qor $lab
qb_done $lab
