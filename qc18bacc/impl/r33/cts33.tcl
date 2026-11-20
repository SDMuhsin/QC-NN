# R33: CTS step replay (flow cts.tcl + the hub PRE_CTS_TCL) from db/place.odb; R33_CKFIX 1: data buffers are dont_use
# during repair_clock_nets (it then has to use the CK cells); R33_DB other than place: just measure that db
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
set _f [open $::OUT/config.tcl]; set _t [read $_f]; close $_f
eval [string map {r31_snap/ r31_snap4/} $_t]
qc_config
set ::STEPS {init floorplan pdn place cts route finish}
set_thread_count 8
set db [qc_env R33_DB place]
qc_load $db
proc ckmeas {tag} {
    set blk [ord::get_db_block]; set nb 0; set names {}
    foreach i [$blk getInsts] {
        set m [$i getMaster]; if {![regexp {^(BUFF|INV)} [$m getName]]} continue
        set o [$i findITerm Z]; if {$o eq "NULL"} { set o [$i findITerm ZN] }; if {$o eq "NULL"} continue
        set n [$o getNet]; if {$n eq "NULL" || [$n getSigType] ne "CLOCK"} continue
        incr nb; lappend names "[$i getName]:[$m getName]"
    }
    puts "R33K $tag non-CK buffers/inverters driving clock nets: $nb ([lrange [lsort $names] 0 30])"
    set pe [lindex [find_timing_paths -to [get_ports u_top_s_wa_3_] -path_delay max -group_count 1] 0]
    puts [format "R33K %s hoy -> s_wa_3 slack %.3f" $tag [expr {[$pe slack] * 1e9}]]
    report_checks -to [get_ports u_top_s_wa_3_] -format full_clock_expanded -fields {slew cap} -digits 3 > /tmp/ckp908/qc18bacc/r33/cts33_${tag}_hoy.rpt
    flush stdout
}
if {$db eq "place"} {
    if {[p PRE_CTS_TCL] ne ""} { source [p PRE_CTS_TCL] }
    clock_tree_synthesis -buf_list $::QC_PNR_CTS_BUF -root_buf $::QC_PNR_CTS_ROOT -sink_clustering_enable \
        -sink_clustering_size [p CTS_CLUSTER_SIZE] -sink_clustering_max_diameter [p CTS_CLUSTER_DIAMETER] {*}[p CTS_ARGS]
    set_propagated_clock [all_clocks]
    if {[qc_env R33_CKFIX 0]} { set_dont_use [get_lib_cells {BUFF* INV*}] }
    repair_clock_nets
    if {[qc_env R33_CKFIX 0]} { unset_dont_use [get_lib_cells {BUFF* INV*}]; set_dont_use $::QC_PNR_DONT_USE }
    detailed_placement {*}[p DPL_ARGS]
    estimate_parasitics -placement
    ckmeas cts_ckfix[qc_env R33_CKFIX 0]
    if {[qc_env R33_ODB ""] ne ""} { write_db $::env(R33_ODB) }
} else {
    set_propagated_clock [all_clocks]
    estimate_parasitics -placement
    ckmeas $db
}
exit
