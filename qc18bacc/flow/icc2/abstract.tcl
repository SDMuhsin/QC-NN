# Block views for the chip top from the routed block (label QB_ICC2_LABEL: route, or eco; blocks/<b>/run.sh views):
#   out/<top>.lef       abstract LEF of the frame view (exact metal shapes as OBS, no merging: the top's ring LEF is
#                       made from it by signoff/etm/lef_ring.py), pins on their routing layers, with the ports' LEF 5.8
#                       hierarchical antenna data of ICC2 (derive_hier_antenna_property on the frame, kit antenna rules
#                       of qb_antenna_rules): ANTENNAPARTIALMETALAREA / PARTIALMETALSIDEAREA / PARTIALCUTAREA per layer
#                       (the block-side metal the top router adds to the net), ANTENNAGATEAREA / DIFFAREA, MAX*CAR (R67:
#                       replaces the gate / diff-only patch of signoff/etm/blkant.py, which gave the top no metal data)
#   gates (error on failure, one summary line each):
#     antenna   every signal PIN of the LEF has ANTENNAPARTIALMETALAREA and ANTENNAPARTIALCUTAREA
#     abutment  every act[b] / act_o[b] pair on the same layer and y, act on the west and act_o on the east die edge
#     pg_pins   qb_pg_check: VDD / VSS pins = the chip PG grid's pin-layer straps (floorplan/pg_grid.tcl)
source [file dirname [info script]]/common.tcl
open_lib $::QB_LIB
open_block $P(TOP)/[qc_env QB_ICC2_LABEL route]
link_block
set o $::R/out/$P(TOP)
qb_antenna_rules
create_frame -block_all false -merge_metal_blockage false
save_block
# (the label-qualified block name: derive_hier_antenna_property on a <lib>:<block>.design name fails, ZRT-554, R67 [M])
derive_hier_antenna_property -design_name $P(TOP)/[qc_env QB_ICC2_LABEL route]
save_block
write_lef -design [get_object_name [current_block]] $o.lef
# antenna gate: per LEF PIN (USE POWER / GROUND excluded) the PARTIAL metal / cut statements
set ag [exec awk {
    /^  PIN /                          { p = $2; pin[p] = 1 }
    /^    USE (POWER|GROUND)/          { pg[p] = 1 }
    /^    ANTENNAPARTIALMETALAREA /    { m[p] = 1 }
    /^    ANTENNAPARTIALCUTAREA /      { c[p] = 1 }
    END { for (p in pin) if (!(p in pg)) { n++; if (!(p in m)) nm++; if (!(p in c)) nc++ }
          printf "%d %d %d", n, nm, nc }
} $o.lef]
lassign $ag np nm nc
set ns [sizeof_collection [get_ports -filter "port_type!=power && port_type!=ground"]]
qb_line "abstract lef [file size $o.lef] bytes, signal PIN $np (ports $ns), antenna partial metal missing $nm, partial cut missing $nc"
if {$np != $ns || $nm || $nc} { error "QB abstract antenna: signal PIN $np of $ns ports, missing PARTIALMETAL $nm PARTIALCUT $nc" }
set die [get_attribute [current_block] boundary_bbox]
set x0 [lindex $die 0 0]; set x1 [lindex $die 1 0]
# (a terminal has no layer_name attribute: get_attribute read "" for both pins of every pair until R67, so the layer
# comparison passed vacuously; layer.name is the layer)
proc qb_term {name} {
    set t [get_terminals -of_objects [get_ports $name]]
    list [get_attribute $t bbox] [get_attribute $t layer.name]
}
set ok 0; set bad {}
foreach_in_collection p [get_ports {act[*]}] {
    regexp {\[(\d+)\]} [get_object_name $p] -> b
    lassign [qb_term "act\[$b\]"] a la; lassign [qb_term "act_o\[$b\]"] y ly
    if {$la ne "" && $la eq $ly && [lindex $a 0 1] == [lindex $y 0 1] && [lindex $a 1 1] == [lindex $y 1 1]
        && [lindex $a 0 0] == $x0 && [lindex $y 1 0] == $x1} { incr ok } else { lappend bad $b }
}
qb_line "abstract abutment act pairs ok $ok bad [llength $bad] [lrange $bad 0 4] die $die"
if {[llength $bad]} { error "QB abstract abutment: [llength $bad] act / act_o pairs off ([lrange $bad 0 4])" }
qb_pg_check abstract
puts "QB_ICC2_DONE abstract"
