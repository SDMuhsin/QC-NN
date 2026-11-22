# R37 (results/r37.md): hub PrimeTime sign-off = signoff/pt/hub.tcl evaluated as is (summary pt_hub_<corner>.txt, reports),
# with one hook right after its IO budget (qb9_io_apply $per $L; update_timing; L = this corner's p50 clock-pin latency):
#   class budget re-split actout 0.26 P (with the act QB7_DIN 0.74: the output delay is the external share)
#   in2out feed-through paths (rst_n / ctl -> column north: input 0.40 P + output 0.55 P = 0.95 P of budget, a
#     constraint bug, r35.md) are reported as internal delay (arrival - input delay) vs 0.20 x P and then set
#     false for setup in this run only; the ETM keeps the arcs, so the chip PT times the real path end to end.
set f [open $::env(R31_PTHUB)]; set t [read $f]; close $f
set k "qb9_io_apply \$per \$L\nupdate_timing\n"
if {[string first $k $t] < 0} { puts "R37 hook point not found"; exit 1 }
proc r37_hook {} {
    upvar #0 per per L L corner corner
    # the same class budget re-split as repair/hub_io.tcl QB37_FR (sdc.py fractions otherwise)
    foreach {k v} {actout 0.26} {
        if {![info exists ::QB9_IO($k)]} continue
        if {[lsearch {colin actin topin hostin} $k] >= 0} { set_input_delay -max [expr {$v * $per + $L}] -clock qb_clk [get_ports $::QB9_IO($k)] } \
        else { set_output_delay -max [expr {$v * $per - $L}] -clock qb_clk [get_ports $::QB9_IO($k)] }
        puts "R37FR $corner class $k max budget $v P"
    }
    update_timing
    puts [format "R37L %s io_shift_L %.3f" $corner $L]
    set fr 0.20
    set ps [get_timing_paths -delay_type max -from [all_inputs] -to [all_outputs] -max_paths 100000 -nworst 1]
    set w -1; set wn ""; set ns 0
    foreach_in_collection p $ps {
        set d [expr {[get_attribute $p arrival] - [get_attribute $p startpoint_input_delay_value]}]
        if {$d > $w} { set w $d; set wn "[get_object_name [get_attribute $p startpoint]] -> [get_object_name [get_attribute $p endpoint]]" }
        if {[get_attribute $p slack] < 0} { incr ns }
    }
    puts [format "R37FT %s in2out endpoints %d (budget-sum violators %d) worst internal delay %.3f ns vs %.2f P = %.3f ns : %s %s" \
        $corner [sizeof_collection $ps] $ns $w $fr [expr {$fr * $per}] [expr {$w <= $fr * $per ? "OK" : "FAIL"}] $wn]
    set_false_path -setup -from [all_inputs] -to [all_outputs]
    update_timing
}
# After the hook, every violating endpoint (setup and hold, worst path each) with its launch / capture clock
# latency -> <run>/rpt/r37_<corner>_viol.txt (diagnosis), then the normal summary
proc r37_viol {} {
    upvar #0 corner corner dir dir
    set f [open $dir/rpt/r37_${corner}_viol.txt w]
    foreach dt {max min} {
        foreach_in_collection p [get_timing_paths -delay_type $dt -max_paths 100000 -nworst 1 -slack_lesser_than 0] {
            puts $f [format "%s %.3f %s -> %s launch_lat %s capture_lat %s" [expr {$dt eq "max" ? "setup" : "hold"}] [get_attribute $p slack] \
                [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]] \
                [get_attribute -quiet $p startpoint_clock_latency] [get_attribute -quiet $p endpoint_clock_latency]]
        }
    }
    close $f
}
set t [string map [list $k "${k}r37_hook\nr37_viol\n"] $t]
eval $t
