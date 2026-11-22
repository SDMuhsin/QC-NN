# Abstract LEF of a routed qb_col_blk run (OpenROAD, in the run dir; blocks/col/run.sh post): write_abstract_lef
# -bloat_factor 0 (exact shapes, results/pnr_pe.md) -> out/<top>.lef; abutment check (every act[b] / act_o[b] pair on the
# same layer and y, on the west / east die edge); check_antennas -> rpt/antenna.rpt
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
qc_load finish
set dir $::OUT
write_abstract_lef -bloat_factor 0 $dir/out/[p TOP].lef
set blk [ord::get_db_block]; set die [$blk getDieArea]; set ok 0; set bad 0
foreach bt [$blk getBTerms] {
    if {![regexp {^act\[(\d+)\]$} [$bt getName] -> b]} { continue }
    set x [lindex [[lindex [$bt getBPins] 0] getBoxes] 0]
    set y [lindex [[lindex [[$blk findBTerm "act_o\[$b\]"] getBPins] 0] getBoxes] 0]
    if {[$x yMin] == [$y yMin] && [$x yMax] == [$y yMax] && [[$x getTechLayer] getName] eq [[$y getTechLayer] getName]
        && [$x xMin] == [$die xMin] && [$y xMax] == [$die xMax]} { incr ok } else { incr bad }
}
puts "QB5_ABUT act pairs ok $ok bad $bad die [expr {[$die dx] / 2000.0}] x [expr {[$die dy] / 2000.0}] um"
if {[catch {check_antennas -report_file $dir/rpt/antenna.rpt} e]} { puts "QB5_ANT error $e" } else { puts "QB5_ANT done" }
exit
