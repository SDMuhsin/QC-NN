# PT hook (results/pnr_slice2.md): impl/pt_hook.tcl + worst setup path per logic class of the qb_core column slice
# (endpoint regex), for the "within 10 % of the critical path" rule: data arrival (launch clock edge 0, ideal clock).
source [file dirname [info script]]/pt_hook.tcl
set classes {
    pe_s1_pop   {u_pe/.*(u_pop/(s_q|u_q))}
    pe_s2_acc   {u_pe/.*(u_acc/acc)}
    pe_cmp_shd  {u_pe/.*(u_cmp|u_shd)}
    br_dec      {u_br/}
    fused_mul   {u_lf/u_rp1/}
    fused_tail  {u_lf/.*(u_rmid|u_rout)/}
    fused_in    {u_lf/.*(u_rin|u_rlate)/}
    wide_s0s1   {u_lw/(x0|m0|p1|r1|sh|om|t0|t1|v)}
    wide_s2     {u_lw/(y2|r2|om2|t2)}
    wide_tail   {u_lw/.*(s3|yu3|om3|t3|y_o|b_o|vld_o)}
}
set paths [get_timing_paths -delay_type max -max_paths 40000 -nworst 1 -slack_lesser_than 100 -group qb_clk]
array set best {}
foreach_in_collection p $paths {
    set e [get_object_name [get_attribute $p endpoint]]
    foreach {cl re} $classes {
        if {[regexp $re $e] && ![info exists best($cl)]} {
            set best($cl) [list [get_attribute $p slack] [get_attribute $p arrival] \
                [get_object_name [get_attribute $p startpoint]] $e]
        }
    }
}
foreach {cl re} $classes {
    if {[info exists best($cl)]} {
        lassign $best($cl) s a sp ep
        puts $fh [format "class %-11s slack_ns %.3f arrival_ns %.3f %s -> %s" $cl $s $a $sp $ep]
    } else { puts $fh "class $cl none_in_worst_40000" }
}
