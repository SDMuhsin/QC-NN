# R8d proposal A check (PT hook): the column-block clk pins get the DC latency -QB_BLK_LAT (0.90 tt / 1.35 ss: the
# block's clock insertion, results/r8d/blk.txt), i.e. a top tree balanced with the block sinks as the R5a IO budget
# assumes; then the R8d class report (pt_xtra.tcl).  Run on a copy dir of a DC run (impl/r8d/run_pt_lat.sh).
set blks [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name==qb_col_blk"]
set lat [expr {$corner eq "ss" ? 1.35 : 0.90}]
set_clock_latency [expr {-$lat}] [get_pins -of_objects $blks -filter "lib_pin_name==clk"]
puts $fh "blk_clk_latency -$lat on [sizeof_collection $blks] blocks"
source [file dirname [info script]]/pt_xtra.tcl
