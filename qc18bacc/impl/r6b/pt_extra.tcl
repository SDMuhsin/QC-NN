# QB_PT_EXTRA of impl/r5b/pt_chip.tcl (results/r6b.md): R5b ETM outlier pins reported separately, classes without them,
# act chain, and a class histogram of the worst endpoints.  Appends to pt_chip_<corner>.txt.
set qx [get_pins -quiet -of_objects $blk -filter "full_name=~*/act\[1160\] || full_name=~*/act\[265\] || full_name=~*/pf\[526\]"]
foreach_in_collection p $qx {
    fl $fh "etm_outlier [get_object_name $p]" [get_timing_paths -delay_type max -max_paths 1 -to $p] $per
}
set ex [add_to_collection $io $qx]
fl $fh reg2reg_x [get_timing_paths -delay_type max -max_paths 1 -exclude $ex] $per
fl $fh top2blk_x [get_timing_paths -delay_type max -max_paths 1 -to [remove_from_collection $bi $qx] -exclude [add_to_collection $io $bo]] $per
set ba [filter_collection $bi "lib_pin_name=~act*"]
set b0 [get_cells -hierarchical -filter "ref_name==qb_col_blk && full_name=~*g_c_0__*"]
set ba0 [filter_collection $ba "full_name=~*g_c_0__*"]
fl $fh act_top2col0 [get_timing_paths -delay_type max -max_paths 1 -to [remove_from_collection $ba0 $qx]] $per
fl $fh act_blk2blk [get_timing_paths -delay_type max -max_paths 1 -from [get_cells $blk] -to [remove_from_collection $ba $qx]] $per
# histogram: worst path per endpoint (up to QB_PT_NHIST, default 20 000) with slack < QB_PT_HSLK (default 0), by class
proc qb6_cls {pin} {
    if {[get_attribute -quiet $pin object_class] eq "port"} { return io }
    set c [get_cells -quiet -of_objects $pin]
    if {![sizeof_collection $c]} { return io }
    set r [get_attribute $c ref_name]
    if {$r eq "qb_col_blk"} { return blk }
    if {[string match qb_*_*x*m* $r]} { return mac }
    return top
}
set nh [expr {[info exists ::env(QB_PT_NHIST)] ? $::env(QB_PT_NHIST) : 20000}]
set hs [expr {[info exists ::env(QB_PT_HSLK)] ? $::env(QB_PT_HSLK) : 0.0}]
array set hn {}; array set hw {}
foreach_in_collection p [get_timing_paths -delay_type max -max_paths $nh -nworst 1 -slack_lesser_than $hs -exclude $ex] {
    set sp [get_attribute $p startpoint]; set ep [get_attribute $p endpoint]
    set k "[qb6_cls $sp]->[qb6_cls $ep]"
    set epn [get_object_name $ep]
    if {[string match blk* [qb6_cls $ep]] && [regexp {/act\[} $epn]} { append k "(act)" }
    set sl [get_attribute $p slack]
    if {![info exists hn($k)]} { set hn($k) 0; set hw($k) $sl }
    incr hn($k); if {$sl < $hw($k)} { set hw($k) $sl }
}
foreach k [lsort [array names hn]] { puts $fh [format "hist slack<%.3f class %s endpoints %d worst %.3f" $hs $k $hn($k) $hw($k)] }
redirect $dir/rpt/pt_chip_${corner}_reg2reg_x.rpt { report_timing -max_paths 20 -nosplit -exclude $ex -input_pins -nets -capacitance -transition_time }
