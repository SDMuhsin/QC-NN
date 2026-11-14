# R5d step 1 (results/r5d.md): every setup-violating endpoint of a routed qb_col_blk PT session, one worst path each,
# with its wire / cell split and max net cap.  Runs impl/r5a/pt_blk.tcl (exit disabled) in a scratch QC_PNR_OUT whose
# out/ links to the routed run, then dumps <QC_PNR_OUT>/viol_<corner>.txt; group it with impl/r5d/hist.py.
#   env as impl/r5a/post.sh pt (QC_PERIOD = the period of the histogram)
rename exit qb5d_exit
proc exit {args} {}
source $::env(QB5D_R5A)/pt_blk.tcl
rename exit {}
rename qb5d_exit exit
set ps [get_timing_paths -delay_type max -max_paths 200000 -nworst 1 -slack_lesser_than 0.0]
set fh [open $::env(QC_PNR_OUT)/viol_$::env(QC_CORNER).txt w]
puts $fh "# slack start end wire_ns cell_ns cells max_cap_pf max_cap_net buf_ns nbuf (buf = BUFF / CKBD / INV / CKND / DEL cells)"
foreach_in_collection p $ps {
    set prev [get_attribute $p startpoint_clock_latency]; set wire 0.0; set cell 0.0; set n 0; set mc 0.0; set mn -; set bd 0.0; set nb 0
    set first 1
    foreach_in_collection pt [get_attribute $p points] {
        set a [get_attribute $pt arrival]; set o [get_attribute $pt object]
        if {$first} { set prev $a; set first 0; continue }
        set d [expr {$a - $prev}]; set prev $a
        set dir [get_attribute -quiet $o direction]
        if {[get_attribute -quiet $o object_class] eq "pin" && $dir eq "in"} { set wire [expr {$wire + $d}] } \
        else { set cell [expr {$cell + $d}]; incr n
               set rc [get_cells -quiet -of_objects $o]
               if {[sizeof_collection $rc] && [regexp {^(BUFF|CKBD|INV|CKND|DEL)} [get_attribute $rc ref_name]]} {
                   set bd [expr {$bd + $d}]; incr nb }
               set net [get_nets -quiet -of_objects $o]
               if {[sizeof_collection $net]} { set c [get_attribute -quiet $net total_capacitance_max]
                   if {$c ne "" && $c > $mc} { set mc $c; set mn [get_object_name $net] } } }
    }
    puts $fh [format "%.4f %s %s %.4f %.4f %d %.4f %s %.4f %d" [get_attribute $p slack] \
        [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]] $wire $cell $n $mc $mn $bd $nb]
}
close $fh
puts "QB5D_HIST [sizeof_collection $ps] paths"
exit
