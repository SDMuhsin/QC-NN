# Sourced by route/top_post_grt.tcl (results/r14.md): max slew / cap violators at GRT parasitics (layer-true RC), by class: pins on hard blocks
# (t2 = hub -> column t2 M8 nets, other block pins) vs top cells -> rpt/drv_post.txt.
set _rf $::OUT/rpt/drv_post.tmp
qc_to $_rf { report_check_types -max_slew -max_capacitance -violators }
array set _dpn {}; array set _dpw {}; set _k slew
set f [open $_rf]
while {[gets $f l] >= 0} {
    if {[string match "*max slew*" $l]} { set _k slew } elseif {[string match "*max capacitance*" $l]} { set _k cap }
    if {![string match *VIOLATED* $l]} { continue }
    set pin [lindex $l 0]; set s [lindex $l 3]
    if {[string match *t2* $pin] && ([string match u_hub/* $pin] || [string match *u_col/* $pin])} { set c t2 } elseif {[string match u_hub/* $pin] || [string match *u_col/* $pin] || [string match u_act_blk/* $pin]} { set c blockpin } elseif {[string match q14_* $pin]} { set c clock } else { set c top }
    set key "$_k/$c"; incr _dpn($key)
    if {![info exists _dpw($key)] || $s < $_dpw($key)} { set _dpw($key) $s }
}
close $f
set o [open $::OUT/rpt/drv_post.txt w]
puts $o "# R14 DRV at GRT parasitics: check/class violators worst_slack"
foreach k [lsort [array names _dpn]] { puts $o [format "%-16s %7d %8.3f" $k $_dpn($k) $_dpw($k)]; qc_summary "r14 drv_post $k $_dpn($k) worst $_dpw($k)" }
close $o
