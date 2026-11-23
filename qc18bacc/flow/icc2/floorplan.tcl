# Floorplan: die P(DIE) with core margin P(CORE_OFFSET) (rows + tracks from the tech file), signal pins at the positions
# of the floorplan DEF P(PIN_DEF) (fixed), PDN: M1 followpin rails + the chip PG grid ::QB_PG_GRID (floorplan/pg_grid.tcl:
# {layer dir width pitch offset}, VSS / VDD pairs, offset = core edge -> low edge of the VSS strap), the straps extended
# to the west / east die edges; the straps of the pin layer ::QB_PG_PIN are the VDD / VSS pins, each across the whole
# die (create_terminal of the strap shapes; R67: ICC2's generated edge pins were 0.8 x 0.8 um at the die edges only, on
# VDD-first straps at core + 5 um, off the chip convention), gated by qb_pg_check; routing layers P(LAYERS).
# Block label init -> floorplan.
source [file dirname [info script]]/common.tcl
qb_open init floorplan
initialize_floorplan -control_type die -boundary $P(DIE) -core_offset $P(CORE_OFFSET)
set_ignored_layers -min_routing_layer [lindex $P(LAYERS) 0] -max_routing_layer [lindex $P(LAYERS) 1]

# supply ports / nets
foreach {n t} {VDD power VSS ground} {
    if {![sizeof_collection [get_ports -quiet $n]]} { create_port -direction inout -port_type $t $n }
    if {![sizeof_collection [get_nets -quiet $n]]} { create_net -$t $n }
    connect_pg_net -net $n [get_ports $n]
}
connect_pg_net -automatic

# signal pins from the DEF (its VDD / VSS pin shapes are replaced by the PDN's own)
read_def -include {ports} $P(PIN_DEF)
set pgt [get_terminals -quiet -of_objects [get_ports {VDD VSS}]]
if {[sizeof_collection $pgt]} { remove_terminals $pgt }
set sig [remove_from_collection [get_ports] [get_ports {VDD VSS}]]
set_attribute $sig physical_status fixed
set nt [sizeof_collection [get_terminals -quiet -of_objects $sig]]

# PDN
set layers {}
# (ICC2's mesh offset is core edge -> first strap centre, the pattern's first net is the first strap)
foreach m $::QB_PG_GRID {
    lassign $m ly dir w pitch off
    lappend layers [list "${dir}_layer: $ly" "width: $w" "spacing: interleaving" "pitch: $pitch" "offset: [expr {$off + $w / 2.0}]"]
}
create_pg_mesh_pattern qb_mesh -layers $layers
create_pg_std_cell_conn_pattern qb_rail -layers {M1}
set_pg_strategy qb_rail -core -pattern {{name: qb_rail} {nets: {VDD VSS}}}
compile_pg -strategies qb_rail
# the lowest strap layer reaches across the whole followpin rail at the core edges: the rails on the bottom / top row
# boundary are centred on the core edge, so a strap clipped at the core put its rail via on half the rail and the via's
# M1 enclosure stuck out of the rail (R54 Calibre G.4:M1i / M1.S.1 at y 5.165-5.170; ICC2 does not check same-net jogs)
set rw [tcl::mathfunc::max {*}[get_attribute [get_shapes -filter "layer_name==M1 && shape_use==lib_cell_pin_connect"] width]]
set lo [lindex [lindex $::QB_PG_GRID 0] 0]
set_pg_strategy qb_mesh -core -pattern {{name: qb_mesh} {nets: {VSS VDD}}} \
    -extension [list {{direction: L R} {stop: design_boundary}} \
                     [list "layers: $lo" {direction: B T} "stop: [expr {$rw / 2.0}]"]]
set_pg_strategy_via_rule qb_via -via_rule [list \
    [list [list {strategies: qb_mesh} "layers: $lo"] {{existing: std_conn} {layers: M1}} {via_master: default}] \
    {{intersection: undefined} {via_master: NIL}}]
compile_pg -strategies qb_mesh -via_rule qb_via
create_terminal -of_objects [get_shapes -filter "layer_name==$::QB_PG_PIN && shape_use==stripe"]
qb_pg_check floorplan
qb_line "floorplan rail_width $rw strap_ext $lo [expr {$rw / 2.0}]"
redirect -tee $::R/rpt/floorplan_pg.rpt { check_pg_connectivity -check_std_cell_pins none; check_pg_drc }

qb_line "floorplan die $P(DIE) core_offset $P(CORE_OFFSET) rows [sizeof_collection [get_site_rows]] signal_ports [sizeof_collection $sig] with_terminals $nt pg_terminals [sizeof_collection [get_terminals -quiet -of_objects [get_ports {VDD VSS}]]]"
qb_done floorplan
