# impl/r7b: timing path classes of the loaded design at the current parasitics (sourced by post_grt.tcl after the
# flow's estimate_parasitics -global_routing).  The worst QB7_NPATH [5000] setup endpoints (one path each, slack < 0)
# are classed by (start kind -> end kind): column-block pin -> 'blk.<bus>', macro -> 'mac.<type>', std cell ->
# its RTL unit (act / seq / prm / head / dist / chip) or 'glue.<register or cell base name>'.
# Output QB7_CLS_OUT [<run>/rpt/grt_classes.txt]: per class count, worst slack, one example; + the worst hold paths.
proc qb7_kind {name} {
    if {[regexp {g_c_(\d+)__u_col/([a-z_0-9]+)} $name -> c b]} { return "blk.$b" }
    if {[regexp {g_mac_g_([a-z0-9]+)_u_mac} $name -> t]} { return "mac.$t" }
    foreach {p k} {u_top/u_act/ act g_rt_u_seq/ seq u_prm/ prm u_head/ head u_top/g_dist_ dist} {
        if {[string first $p $name] >= 0} {
            if {$k in {prm head} && [regexp {/([a-z][a-z0-9_]*?)_reg} $name -> r]} { return "$k.$r" }
            return $k
        }
    }
    if {[regexp {^u_top/([a-z][a-z0-9_]*?)_reg} $name -> r]} { return "glue.$r" }
    if {[string first / $name] < 0 || [string match PORT* $name]} { return chip }
    return glue
}
proc qb7_classes {} {
    set out [qb_env QB7_CLS_OUT $::OUT/rpt/grt_classes.txt]
    set n [qb_env QB7_NPATH 5000]
    set fh [open $out w]
    puts $fh "# worst setup WNS [format %.3f [sta::worst_slack_cmd max]] ns, hold [format %.3f [sta::worst_slack_cmd min]] ns"
    foreach {dly tag} {max setup min hold} {
        if {[catch {set paths [find_timing_paths -path_delay $dly -group_count $n -endpoint_count 1 -slack_max 0]}]} {
            set paths [find_timing_paths -path_delay $dly -group_path_count $n -endpoint_path_count 1 -slack_max 0]
        }
        array unset C; array set C {}
        foreach p $paths {
            set s [get_full_name [get_property $p startpoint]]; set e [get_full_name [get_property $p endpoint]]
            set k "[qb7_kind $s] -> [qb7_kind $e]"
            set sl [get_property $p slack]
            if {![info exists C($k)]} { set C($k) [list 0 $sl "$s -> $e"] }
            lassign $C($k) cn w ex
            if {$sl < $w} { set w $sl; set ex "$s -> $e" }
            set C($k) [list [incr cn] $w $ex]
        }
        puts $fh "## $tag: [llength $paths] endpoints (of the worst $n), by class: count worst_ns example"
        foreach k [lsort -command {apply {{a b} {upvar C C; expr {[lindex $C($a) 1] < [lindex $C($b) 1] ? -1 : 1}}}} [array names C]] {
            lassign $C($k) cn w ex
            puts $fh [format "%-40s %6d %8.3f  %s" $k $cn $w $ex]
        }
    }
    close $fh
    qc_log "r7b: path classes -> $out"
}
