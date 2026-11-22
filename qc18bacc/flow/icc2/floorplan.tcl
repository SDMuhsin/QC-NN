# Floorplan: die P(DIE) with core margin P(CORE_OFFSET) (rows + tracks from the tech file), signal pins at the positions
# of the floorplan DEF P(PIN_DEF) (fixed), PDN: M1 followpin rails + the P(PDN_MESH) straps {layer dir width pitch
# offset} as VDD / VSS pairs, horizontal straps extended to the west / east edges as VDD / VSS pins; routing layers
# P(LAYERS).  Block label init -> floorplan.
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
foreach m $P(PDN_MESH) {
    lassign $m ly dir w pitch off
    lappend layers [list "${dir}_layer: $ly" "width: $w" "spacing: interleaving" "pitch: $pitch" "offset: $off"]
}
create_pg_mesh_pattern qb_mesh -layers $layers
create_pg_std_cell_conn_pattern qb_rail -layers {M1}
set_pg_strategy qb_mesh -core -pattern {{name: qb_mesh} {nets: {VDD VSS}}} \
    -extension {{direction: L R} {stop: design_boundary_and_generate_pin}}
set_pg_strategy qb_rail -core -pattern {{name: qb_rail} {nets: {VDD VSS}}}
set lo [lindex [lindex $P(PDN_MESH) 0] 0]
set_pg_strategy_via_rule qb_via -via_rule [list \
    [list [list {strategies: qb_mesh} "layers: $lo"] {{strategies: qb_rail} {layers: M1}} {via_master: default}] \
    {{intersection: undefined} {via_master: NIL}}]
compile_pg -strategies {qb_mesh qb_rail} -via_rule qb_via
redirect -tee $::R/rpt/floorplan_pg.rpt { check_pg_connectivity -check_std_cell_pins none; check_pg_drc }

qb_line "floorplan die $P(DIE) core_offset $P(CORE_OFFSET) rows [sizeof_collection [get_site_rows]] signal_ports [sizeof_collection $sig] with_terminals $nt pg_terminals [sizeof_collection [get_terminals -quiet -of_objects [get_ports {VDD VSS}]]]"
qb_done floorplan
