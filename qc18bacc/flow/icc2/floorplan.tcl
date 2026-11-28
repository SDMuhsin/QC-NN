# Floorplan: die P(DIE) with core margin P(CORE_OFFSET) = {left bottom right top} (rows from the tech file's site, tracks
# at the kit LEF phase against the rows, gated by qb_track_check), signal pins at the positions
# of the floorplan DEF P(PIN_DEF) (fixed), PDN: M1 followpin rails + the chip PG grid ::QB_PG_GRID (floorplan/pg_grid.tcl:
# {layer dir width pitch offset}, VSS / VDD pairs, offset = core edge -> low edge of the VSS strap), the straps extended
# to the west / east die edges; the straps of the pin layer ::QB_PG_PIN are the VDD / VSS pins, each across the whole
# die (create_terminal of the strap shapes; R67: ICC2's generated edge pins were 0.8 x 0.8 um at the die edges only, on
# VDD-first straps at core + 5 um, off the chip convention), gated by qb_pg_check; routing layers P(LAYERS).
# Block label init -> floorplan.
source [file dirname [info script]]/common.tcl
qb_open init floorplan
# Kit track phase (R92): ICC2 starts a layer's tracks at core origin + the layer's track_offset, and the design library's
# tech (tf) has none, so they ran along the cell boundaries (common.tcl qb_track_check).  A LEF OFFSET counts from the
# design origin: track_offset = (LEF OFFSET - core origin across the wires) mod PITCH puts every LEF grid layer's tracks at
# OFFSET + k PITCH in the die frame, also where the pitch does not divide the core offset (M8 / M9: 5.0 mod 0.8 = 0.2);
# the rows and the block pins stay ([M] the M2 / M4 / M6 pins are at x = 0.1 + 0.2 k).  (-core_offset: 1, {x y} or
# {left bottom right top} values.)
set _c0 [list [expr {[lindex $P(DIE) 0 0] + [lindex $P(CORE_OFFSET) 0]}] [expr {[lindex $P(DIE) 0 1] + [lindex $P(CORE_OFFSET) [expr {[llength $P(CORE_OFFSET)] > 1}]]}]]
foreach {ly g} [qb_lef_grid] {
    lassign $g d p o
    set _c [lindex $_c0 [expr {$d ne "vertical"}]]
    set_attribute [get_layers $ly] track_offset [expr {(round(($o - $_c) * $::QB_DBU) % round($p * $::QB_DBU)) / double($::QB_DBU)}]
}
initialize_floorplan -control_type die -boundary $P(DIE) -core_offset $P(CORE_OFFSET)
set_ignored_layers -min_routing_layer [lindex $P(LAYERS) 0] -max_routing_layer [lindex $P(LAYERS) 1]

# supply ports / nets
foreach {n t} {VDD power VSS ground} {
    if {![sizeof_collection [get_ports -quiet $n]]} { create_port -direction inout -port_type $t $n }
    if {![sizeof_collection [get_nets -quiet $n]]} { create_net -$t $n }
    connect_pg_net -net $n [get_ports $n]
}
connect_pg_net -automatic

# signal pins from the DEF (its VDD / VSS pin shapes are replaced by the PDN's own).  Every DEF pin is a port of the
# netlist (R114; hunt round 15 on f8f6eee: read_def -include ports drops a pin without a port silently, so a stale pin
# of the reference abstract, e.g. the column's COL_REFLEF, went unseen): its PINS section is read here first, error on
# an unparsed section (pin count = its PINS N) or on any pin name that is no port
proc qb_def_pins {def} {   ;# (line by line: a regexp over the whole PINS section took minutes on the column's 1.7 MB DEF)
    set f [open $def]; set n -1; set in 0; set pins {}
    while {[gets $f l] >= 0} {
        if {!$in} { if {[regexp {^\s*PINS\s+(\d+)\s*;} $l -> n]} { set in 1 }; continue }
        if {[regexp {^\s*END\s+PINS\s*$} $l]} { set in 2; break }
        if {[regexp {^\s*-\s+(\S+)} $l -> p]} { lappend pins $p }
    }
    close $f
    if {$in != 2} { error "floorplan: no complete PINS section in $def" }
    if {[llength $pins] != $n} { error "floorplan: $def PINS $n, [llength $pins] pin lines parsed" }
    return $pins
}
foreach p [get_object_name [get_ports]] { set _port($p) 1 }
set _dp [qb_def_pins $P(PIN_DEF)]
set _stale [lmap p $_dp { if {[info exists _port($p)]} continue; set p }]
if {[llength $_stale]} { error "floorplan: [llength $_stale] of [llength $_dp] pins of $P(PIN_DEF) are no netlist port: [lrange $_stale 0 19]" }
qb_line "floorplan pin_def pins [llength $_dp], each a netlist port"
read_def -include {ports} $P(PIN_DEF)
set pgt [get_terminals -quiet -of_objects [get_ports {VDD VSS}]]
if {[sizeof_collection $pgt]} { remove_terminals $pgt }
set sig [remove_from_collection [get_ports] [get_ports {VDD VSS}]]
set_attribute $sig physical_status fixed
set nt [sizeof_collection [get_terminals -quiet -of_objects $sig]]
# every signal port has a pin from the DEF (R102; before, the counts were only logged, so a port the pin DEF missed went
# on with no terminal)
set nopin {}
foreach_in_collection q $sig { if {![sizeof_collection [get_terminals -quiet -of_objects $q]]} { append_to_collection nopin $q } }
if {[sizeof_collection $nopin]} {
    error "floorplan: [sizeof_collection $nopin] of [sizeof_collection $sig] signal ports have no terminal from $P(PIN_DEF): [lrange [get_object_name $nopin] 0 19]"
}
qb_track_check floorplan $sig

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
