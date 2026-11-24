# Block views for the chip top from the routed block (label QB_ICC2_LABEL: route, or eco, copied to label abstract;
# blocks/<b>/run.sh views):
#   out/<top>.lef       abstract LEF of the frame view, pins on their routing layers, every block routing layer (P(LAYERS):
#                       M1 .. its top layer, M7) one zero-spacing blockage over the whole die except around the pins
#                       (create_frame -block_all <top layer>; R71 PI decision: the GDS carries ~321k Calibre DM7 fill
#                       shapes that no exact-shape OBS showed, so the top may not route M1 .. M7 over a column; M8 / M9
#                       stay free for the top), with the ports' LEF 5.8
#                       hierarchical antenna data of ICC2 (derive_hier_antenna_property on the frame, kit antenna rules
#                       of qb_antenna_rules): ANTENNAPARTIALMETALAREA / PARTIALMETALSIDEAREA / PARTIALCUTAREA per layer
#                       (the block-side metal the top router adds to the net), ANTENNAGATEAREA / DIFFAREA, MAX*CAR (R67:
#                       replaces the gate / diff-only patch of signoff/etm/blkant.py, which gave the top no metal data)
#   gates (error on failure, one summary line each):
#     antenna   every signal PIN of the LEF has ANTENNAPARTIALMETALAREA and ANTENNAPARTIALCUTAREA
#     blockage  OBS on every metal layer up to P(LAYERS)'s top layer, none above (R71)
#     abutment  every act[b] / act_o[b] pair on the same layer and y, act on the west and act_o on the east die edge
#     pg_pins   qb_pg_check: VDD / VSS pins = the chip PG grid's pin-layer straps (floorplan/pg_grid.tcl)
# The frame and its antenna data are made on a copy, block label "abstract" (R77): the label QB_ICC2_LABEL is the signed-off
# design (post / calibre read its outputs) and is never saved after its own step (R75 saved the frame into label eco).
source [file dirname [info script]]/common.tcl
qb_open [qc_env QB_ICC2_LABEL route] abstract
set o $::R/out/$P(TOP)
qb_antenna_rules
create_frame -block_all [lindex $P(LAYERS) end]
save_block
# (the label-qualified block name: derive_hier_antenna_property on a <lib>:<block>.design name fails, ZRT-554, R67 [M])
derive_hier_antenna_property -design_name $P(TOP)/abstract
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
# blockage gate (R71): OBS on every metal layer up to the block's top routing layer, none above it (the top's layers);
# per layer the summed OBS RECT + POLYGON area / die area (the blockage less the pin cut-outs) is logged (R72: write_lef
# gives the cut-out blockage of the pin layers as POLYGONs, up to ~2300 per layer [M]; RECT-only logged M2 0.000);
# a POLYGON may continue over several lines up to its ';' (shoelace area)
set ob [exec awk {
    function poly(   i, s) { s = 0; for (i = 1; i + 3 <= n; i += 2) s += v[i] * v[i + 3] - v[i + 2] * v[i + 1]
                             s += v[n - 1] * v[2] - v[1] * v[n]; return (s < 0 ? -s : s) / 2 }
    /^  OBS/                  { o = 1; next }
    o && $1 == "END"          { o = 0; next }
    o && $1 == "LAYER"        { l = $2; next }
    o && $1 == "RECT"         { a[l] += ($4 - $2) * ($5 - $3); next }
    o && $1 == "POLYGON"      { p = 1; n = 0; $1 = "" }
    o && p                    { for (i = 1; i <= NF; i++) { t = $i; e = sub(/;$/, "", t); if (t != "") v[++n] = t + 0
                                                            if (e) { p = 0; a[l] += poly(); break } } }
    END { for (l in a) printf "%s %.1f ", l, a[l] }
} $o.lef]
array set oba $ob
set da [expr {([lindex $die 1 0] - $x0) * ([lindex $die 1 1] - [lindex $die 0 1])}]
set top [lindex $P(LAYERS) end]; set bad {}; set cov {}
foreach l [lsort -dictionary [get_object_name [get_layers M?]]] {
    set below [expr {[string range $l 1 end] <= [string range $top 1 end]}]
    set a [expr {[info exists oba($l)] ? $oba($l) : 0.0}]
    lappend cov [format "%s %.3f" $l [expr {$a / $da}]]
    if {$below != ($a > 0)} { lappend bad $l }
}
qb_line "abstract obs (area / die) [join $cov {, }] top_blocked $top bad [llength $bad] $bad"
if {[llength $bad]} { error "QB abstract blockage: OBS missing up to $top or present above it on $bad" }
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
