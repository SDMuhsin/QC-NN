# QC_HOOK of the R5b top DC (impl/r5b/run.sh syn): impl/r4/dc_hook.tcl (macros dont_touch, macro clock gates size-only,
# topographical utilisation) + the column-block ETMs: dont_touch, and their clock pins given a latency of -L (the block's
# clock insertion delay, QB_BLK_LAT, default 0.90 ns tt, results/r5d/pt_blk_r5dB_tt.txt), so that with ideal clocks the
# ETM arcs (which include L) see a top tree balanced with the block's internal sinks, as P&R builds it
# (CTS -insertion_delay) and as the R5a IO budgets assume.
source [file dirname [info script]]/../r4/dc_hook.tcl
set blks [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name==qb_col_blk"]
puts "QB_R5B_BLOCKS [sizeof_collection $blks]"
if {[sizeof_collection $blks]} {
    set_dont_touch $blks
    set_clock_latency [expr {-[qc_env QB_BLK_LAT 0.90]}] [get_pins -of_objects $blks -filter "lib_pin_name==clk"]
}
# act nets of the abutted array (column c act_o -> column c + 1 act, pins at the same y on the shared edge): no
# buffering (P&R has no room between the blocks); DC topographical otherwise buffers them as if the blocks were apart.
if {[sizeof_collection $blks] && [qc_env QB_ACT_DT 1]} {
    set an [get_nets -quiet -of_objects [get_pins -quiet -of_objects $blks -filter "name=~act*"]]
    puts "QB_R5B_ACT_NETS dont_touch [sizeof_collection $an]"
    if {[sizeof_collection $an]} { set_dont_touch $an }
}
# ETM extraction outliers (QB_ETM_FP): setup arcs > 2.5 ns on 3 pins of the R5d block ETM (tt: act[1160] 11.28,
# pf[526] 6.66, act[265] 3.15 ns) while the block's own routed PT gives act -> reg +0.528 ns at 2.0 ns (worst act
# arrival 2.06 ns); excluded here and reported separately in R5b.
foreach p [qc_env QB_ETM_FP {act[1160] pf[526] act[265]}] {
    set fp [get_pins -quiet -of_objects $blks -filter "name==$p"]
    if {[sizeof_collection $fp]} { set_false_path -to $fp }
}
