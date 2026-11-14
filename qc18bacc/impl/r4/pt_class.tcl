# PT hook of impl/r4/run.sh: fmax (impl/pt_hook.tcl) + worst setup path per chip path class (endpoint / startpoint
# hierarchy regex; first match in the worst 200 000 paths, nworst 1 per endpoint), and the worst path per class pair
# for macro boundaries.  fmax of a class = 1 / (period - slack).
source [file dirname [info script]]/../pt_hook.tcl
set per [get_attribute [get_clocks qb_clk] period]
# class {endpoint regex} {startpoint regex or .*}
set classes {
    core_pe_pop    {u_core/.*u_pe.*/u_pop/}            {.*}
    core_pe_acc    {u_core/.*u_pe.*/u_acc/}            {.*}
    core_pe_cmp    {u_core/.*u_pe.*/(u_cmp|u_shd)/}    {.*}
    core_br_dec    {u_core/.*(u_br|u_dec|coldec)}      {.*}
    core_lane_f    {u_core/.*u_lf}                     {.*}
    core_lane_w    {u_core/.*u_lw}                     {.*}
    core_other     {u_top/u_core/}                     {.*}
    act_supply     {u_top/u_act/}                      {.*}
    seq            {u_top/g_r3b_u_seq/|u_top/g_r3b/u_seq/|u_seq/} {.*}
    prm            {u_prm/}                            {.*}
    head           {u_head/}                           {.*}
    to_macro       {/u_mac/}                           {.*}
    from_macro     {.*}                                {/u_mac/}
    top_glue       {u_top/[^/]*$}                      {.*}
    out_port       {^[^/]*$}                           {.*}
}
set paths [get_timing_paths -delay_type max -max_paths 200000 -nworst 1 -slack_lesser_than 100 -group qb_clk]
array set best {}
foreach_in_collection p $paths {
    set e [get_object_name [get_attribute $p endpoint]]
    set s [get_object_name [get_attribute $p startpoint]]
    foreach {cl re rs} $classes {
        if {![info exists best($cl)] && [regexp $re $e] && [regexp $rs $s]} {
            set best($cl) [list [get_attribute $p slack] [get_attribute $p arrival] $s $e]
        }
    }
}
foreach {cl re rs} $classes {
    if {[info exists best($cl)]} {
        lassign $best($cl) sl a sp ep
        puts $fh [format "class %-11s slack_ns %.3f fmax_mhz %.1f arrival_ns %.3f %s -> %s" $cl $sl \
            [expr {1000.0 / ($per - $sl)}] $a $sp $ep]
    } else { puts $fh "class $cl none_in_worst_200000" }
}
# flip-flops per block (ref_name *DF*: DFQD / DFCNQD / EDFQD ...), for the R4 area table
set regs [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~*DF*"]
puts $fh "regs_total [sizeof_collection $regs]"
foreach {cl pat} {core_pe u_top/u_core/*u_pe/* core_lane_f u_top/u_core/*u_lf/* core_lane_w u_top/u_core/*u_lw/*
                  core_all u_top/u_core/* act u_top/u_act/* seq u_top/*u_seq/* prm u_top/*u_prm/* head u_head/*
                  u_top_all u_top/*} {
    puts $fh "regs $cl [sizeof_collection [filter_collection $regs "full_name=~$pat"]]"
}
# R3b token path (open item r3b.md 4.1): worst path through qb_seq's tile-token output tgo, and through its d_eot input
foreach {cl pins} {token_tgo {u_top/*u_seq/tgo*} token_deot {u_top/*u_seq/d_eot}} {
    set pp [get_pins -quiet $pins]
    if {[sizeof_collection $pp]} {
        set p [get_timing_paths -delay_type max -max_paths 1 -through $pp]
        if {[sizeof_collection $p]} {
            set sl [get_attribute $p slack]
            puts $fh [format "class %-11s slack_ns %.3f fmax_mhz %.1f arrival_ns %.3f %s -> %s" $cl $sl \
                [expr {1000.0 / ($per - $sl)}] [get_attribute $p arrival] [get_object_name [get_attribute $p startpoint]] \
                [get_object_name [get_attribute $p endpoint]]]
            redirect -append $out/rpt/pt_${corner}_token.rpt { report_timing -through $pp -nosplit -input_pins }
        }
    } else { puts $fh "class $cl no_pins" }
}
