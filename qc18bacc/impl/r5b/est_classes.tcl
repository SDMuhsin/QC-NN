# impl/r5b: placement-based timing of a chip checkpoint (QB_FROM, default cts) with OpenROAD estimates
# (estimate_parasitics -placement, propagated clock after CTS), block ETM arcs, worst path per class:
#   top2top (top flops only) / top2blk (to a column-block input pin) / blk2top (from a block) / top2top (no block pin) / mac
# -> <run>/rpt/est_<step>.txt (+ full reports est_<step>_<class>.rpt).
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QC_PNR_THREADS 8]
set ::STEPS {init floorplan pdn place cts route finish}
set s [qc_env QB_FROM cts]
qc_load $s
if {$s eq "cts" || $s eq "route"} { set_propagated_clock [all_clocks] }
estimate_parasitics -placement
set blk [get_cells -hierarchical -filter "ref_name == qb_col_blk" *]
set mac {}
foreach i [qc_macros] { if {[[$i getMaster] getName] ne "qb_col_blk"} { lappend mac [$i getName] } }
set bi [get_pins -of_objects $blk -filter "direction == input"]
set bo [get_pins -of_objects $blk -filter "direction == output"]
set io [concat [all_inputs] [all_outputs]]
set fh [open $::OUT/rpt/est_$s.txt w]
set per [get_property [get_clocks qb_clk] period]
puts $fh "step $s period $per blocks [llength $blk] macros [llength $mac] worst_slack [format %.3f [sta::worst_slack_cmd max]]"
proc cls {fh name args} {
    global per
    set paths [find_timing_paths -path_delay max -group_count 1 {*}$args]
    if {![llength $paths]} { puts $fh "$name none"; return }
    set p [lindex $paths 0]
    set sl [get_property $p slack]
    puts $fh [format "%s slack_ns %.3f fmax_mhz %.1f %s -> %s" $name $sl [expr {1000.0 / ($per - $sl)}] \
        [get_full_name [get_property $p startpoint]] [get_full_name [get_property $p endpoint]]]
    qc_to $::OUT/rpt/est_[qc_env QB_FROM cts]_$name.rpt { report_checks -path_delay max {*}$args -fields {slew cap fanout} -digits 3 }
}
cls $fh top2top -from [all_registers -clock_pins] -to [all_registers -data_pins]
cls $fh top2blk -to $bi
cls $fh blk2top -from $blk
# top2blk without the 3 ETM outlier pins (section 1 of results/r5b.md)
set bi2 {}
foreach p $bi { if {![regexp {/(act\[1160\]|act\[265\]|pf\[526\])$} [get_full_name $p]]} { lappend bi2 $p } }
cls $fh top2blk_x -to $bi2
cls $fh act     -to [get_pins -of_objects $blk -filter "name =~ act*"]
cls $fh any
close $fh
qc_log "est_classes $s done"
exit
