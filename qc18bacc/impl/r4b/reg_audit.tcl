# R4b area audit (from the R4 .ddc): per non-core block, flip-flop area / count grouped by register base name (indices
# stripped), plus leaf-cell area directly in each hierarchy level.  Env as dc_rpt.tcl (QC_FLOW, QC_EXTRA_DB_TT, SYN,
# OUT).  Output: $OUT/reg_audit.txt (summaries only).
source $::env(QC_FLOW)/common/lib.tcl
set_app_var search_path [concat . $::QC_LIBDIR [get_app_var search_path]]
set_app_var target_library [list [qc_db tt]]
set_app_var link_library [concat * [qc_db tt] [qc_extra_dbs tt] dw_foundation.sldb]
read_ddc $::env(SYN)/qb_chip.ddc
current_design qb_chip
link
set fh [open $::env(OUT)/reg_audit.txt w]
foreach {blk pat} {top_glue u_top/* seq u_top/g_r3b_u_seq/* prm u_top/g_r3b_u_prm/* act u_top/u_act/* head u_head/*} {
    set regs [get_cells -quiet -hierarchical -filter "is_hierarchical==false && is_sequential==true && full_name=~$pat"]
    if {$blk eq "top_glue"} { set regs [filter_collection $regs "full_name!~u_top/u_core/* && full_name!~u_top/u_act/* && full_name!~u_top/g_r3b_u_seq/* && full_name!~u_top/g_r3b_u_prm/*"] }
    array unset ga; array unset gn
    foreach_in_collection c $regs {
        set n [get_object_name $c]
        regsub {_reg(_[0-9]+_)*$} $n {} k
        regsub -all {_[0-9]+__} $k {_*_} k
        regsub -all {\[[0-9]+\]} $k {[*]} k
        if {![info exists ga($k)]} { set ga($k) 0; set gn($k) 0 }
        set ga($k) [expr {$ga($k) + [get_attribute $c area]}]
        incr gn($k)
    }
    set tot 0; foreach k [array names ga] { set tot [expr {$tot + $ga($k)}] }
    puts $fh [format "BLOCK %s regs %d reg_area_um2 %.0f" $blk [sizeof_collection $regs] $tot]
    foreach k [lsort -command {apply {{a b} {upvar ga ga; expr {$ga($a) < $ga($b) ? 1 : -1}}}} [array names ga]] {
        if {$ga($k) > 300} { puts $fh [format "  %-70s n %6d um2 %9.0f" $k $gn($k) $ga($k)] }
    }
}
# leaf (non-sequential) area directly in qb_top (glue comb) and per sub-hierarchy of qb_top other than core
foreach {blk pat} {top_comb u_top/* seq_comb u_top/g_r3b_u_seq/* prm_comb u_top/g_r3b_u_prm/* act_comb u_top/u_act/*} {
    set cc [get_cells -quiet -hierarchical -filter "is_hierarchical==false && is_sequential==false && full_name=~$pat"]
    if {$blk eq "top_comb"} { set cc [filter_collection $cc "full_name!~u_top/u_core/* && full_name!~u_top/u_act/* && full_name!~u_top/g_r3b_u_seq/* && full_name!~u_top/g_r3b_u_prm/* && full_name!~u_top/g_*u_m/*"] }
    set a 0; foreach_in_collection c $cc { set a [expr {$a + [get_attribute $c area]}] }
    puts $fh [format "COMB %s cells %d um2 %.0f" $blk [sizeof_collection $cc] $a]
}
redirect -variable hv { report_area -hierarchy -nosplit }
foreach l [split $hv "\n"] { if {[regexp {^u_top/(u_act/[^/ ]+|g_r3b_u_seq/[^/ ]+|g_r3b_u_prm/[^/ ]+|[^/ ]+)\s} $l]} { puts $fh "HIER $l" } }
close $fh
puts "QB_AUDIT done"
exit
