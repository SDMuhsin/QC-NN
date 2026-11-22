# Outputs of the routed block (label route) to <run>/out for sign-off (blocks/<b>/run.sh post / calibre):
#   <top>.v         netlist for PrimeTime (no PG, no physical-only cells)
#   <top>_pg.v      netlist with PG connections and physical cells for the Calibre LVS source (signoff/calibre/lvs_src.sh)
#   <top>.def.gz    DEF;  <top>.gds  GDS (1000 dbu / um, the Calibre decks' precision) with the kit cell GDS merged, pin text on the TSMC text layers
#   <top>_<c>_pt.spef  ICC2 extraction (TLU+ of corner c; no StarRC nxtgrd for the 6X2Z stack in the kit)
source [file dirname [info script]]/common.tcl
open_lib $::QB_LIB
open_block $P(TOP)/route
link_block
qb_timer
set o $::R/out/$P(TOP)
write_verilog -hierarchy all -exclude {leaf_module_declarations pg_objects end_cap_cells well_tap_cells filler_cells \
    pad_spacer_cells physical_only_cells cover_cells} $o.v
write_verilog -hierarchy all -exclude {leaf_module_declarations filler_cells} $o\_pg.v
write_def -compress gzip $o.def.gz
set f [open $::R/out/gds_text.map w]
# tsmcn65 tf: metal Mi is layer 30 + i, its pin text layer 130 + i (TEXT1..9, the LVS deck's TEXT LAYER 131..139)
foreach l [get_object_name [get_layers M?]] { set n [expr {30 + [string range $l 1 end]}]; puts $f "text $n:*:*:* [expr {100 + $n}]:0" }
close $f
write_gds -units 1000 -long_names -layer_map $::R/out/gds_text.map -merge_files [list $::QC_PNR_GDS] -output_pin all $o.gds
update_timing -full
write_parasitics -output $o
foreach c $::QC_CORNERS {
    set s [lindex [glob -nocomplain $o.${c}_*.spef] 0]
    if {$s ne ""} { file rename -force $s ${o}_${c}_pt.spef }
    qb_line "outputs spef $c [expr {[file exists ${o}_${c}_pt.spef] ? [file size ${o}_${c}_pt.spef] : "MISSING"}]"
}
qb_line "outputs [join [lmap x [glob $::R/out/*] { file tail $x }] { }]"
puts "QB_ICC2_DONE outputs"
