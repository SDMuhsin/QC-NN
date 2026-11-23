# Block views for the chip top from the routed block (label QB_ICC2_LABEL: route, or eco; blocks/<b>/run.sh views):
#   out/<top>.lef       abstract LEF of the frame view (exact metal shapes as OBS, no merging: the top's ring LEF is
#                       made from it by signoff/etm/lef_ring.py), pins on their routing layers
#   out/blkant.txt      per signal port the leaf pins on its net, "port master pin in|out" (the input of
#                       signoff/etm/blkant.py, as the OpenROAD-era blkant.tcl); out/<top>_ant.lef = the LEF with the
#                       ports' ANTENNAGATEAREA / ANTENNADIFFAREA from the cell LEF (site/pnr.tcl QC_PNR_LEF), env QB_PY
#   abutment check: every act[b] / act_o[b] pair on the same layer and y, act on the west and act_o on the east die edge
source [file dirname [info script]]/common.tcl
open_lib $::QB_LIB
open_block $P(TOP)/[qc_env QB_ICC2_LABEL route]
link_block
set o $::R/out/$P(TOP)
create_frame -block_all false -merge_metal_blockage false
write_lef -design [get_object_name [current_block]] $o.lef
qb_line "abstract lef [file size $o.lef] bytes, PIN [regexp -all -line {^\s*PIN } [exec cat $o.lef]]"
set die [get_attribute [current_block] boundary_bbox]
set x0 [lindex $die 0 0]; set x1 [lindex $die 1 0]
proc qb_term {name} {
    set t [get_terminals -of_objects [get_ports $name]]
    list [get_attribute $t bbox] [get_attribute $t layer_name]
}
set ok 0; set bad {}
foreach_in_collection p [get_ports {act[*]}] {
    regexp {\[(\d+)\]} [get_object_name $p] -> b
    lassign [qb_term "act\[$b\]"] a la; lassign [qb_term "act_o\[$b\]"] y ly
    if {$la eq $ly && [lindex $a 0 1] == [lindex $y 0 1] && [lindex $a 1 1] == [lindex $y 1 1]
        && [lindex $a 0 0] == $x0 && [lindex $y 1 0] == $x1} { incr ok } else { lappend bad $b }
}
qb_line "abstract abutment act pairs ok $ok bad [llength $bad] [lrange $bad 0 4] die $die"
set f [open $::R/out/blkant.txt w]; set n 0
foreach_in_collection p [get_ports -filter "port_type==signal"] {
    set net [get_nets -quiet -of_objects $p]; if {![sizeof_collection $net]} continue
    foreach_in_collection q [get_pins -quiet -physical_context -of_objects $net] {
        set d [get_attribute $q direction]
        puts $f "[get_object_name $p] [get_attribute [get_cells -of_objects $q] ref_name] [get_attribute $q name] [expr {$d eq "in" || $d eq "out" ? $d : "x"}]"
    }
    incr n
}
close $f
qb_line "abstract blkant ports $n: [exec $::env(QB_PY) -I $::QBF/signoff/etm/blkant.py $::QC_PNR_LEF $::R/out/blkant.txt $o.lef ${o}_ant.lef | tail -1]"
puts "QB_ICC2_DONE abstract"
