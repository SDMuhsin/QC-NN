# Outputs of the routed block (label QB_ICC2_LABEL: route, or eco after blocks/<b>/run.sh eco) to <run>/out for sign-off
# (blocks/<b>/run.sh post / calibre):
#   <top>.v         netlist for PrimeTime (no PG, no physical-only cells)
#   <top>_pg.v      netlist with PG connections and physical cells for the Calibre LVS source (signoff/calibre/lvs_src.sh)
#   <top>.def.gz    DEF;  <top>.gds  GDS (::QB_DBU = 1000 dbu / um: the tech file's and the design library's precision, the Calibre decks' PRECISION) with the kit cell GDS merged, pin text on the TSMC text layers
#   (the SPEFs come from flow/icc2/extract.tcl after the Calibre dummy metal fill of this GDS, R68)
#   label.txt       the block label these outputs were written from (blocks/<b>/run.sh eco starts the next ECO round there)
source [file dirname [info script]]/common.tcl
open_lib $::QB_LIB
set label [qc_env QB_ICC2_LABEL route]
open_block $P(TOP)/$label
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
write_gds -units $::QB_DBU -long_names -layer_map $::R/out/gds_text.map -merge_files [list $::QC_PNR_GDS] -output_pin all $o.gds
set f [open $::R/out/label.txt w]; puts $f $label; close $f
qb_line "outputs [join [lmap x [glob $::R/out/*] { file tail $x }] { }]"
puts "QB_ICC2_DONE outputs"
