# R43 opt-in QB43_GRTANT 1 for impl/r35/shim/post_grt.tcl (results/r43.md, defect 5): antenna repair of the top at GRT
# (the top flow stops after GRT and runs DR in a fresh process, so route.tcl's repair_antennas never ran; r39_v: 89
# nets after DR).  Repair against the LEF rule as the sign-off check impl/r29/antd29.tcl reads it (this OR applies the
# scalar CAR and never the diffusion PWL): scalar CAR of M1-M8 set to 0 in memory for the repair, restored after (the
# db keeps the LEF values).  QB43_ANT_MARGIN [25] % headroom for the GRT -> DRT length change (R40 hub: 3 nets at
# 1.04-1.27x without margin), QB43_ANT_ITER [3].
proc q43_ant {} {
    set t [clock seconds]; array set car {}
    foreach ln {M1 M2 M3 M4 M5 M6 M7 M8} {
        set l [[[ord::get_db] getTech] findLayer $ln]
        if {$l eq "NULL" || ![$l hasDefaultAntennaRule]} continue
        set r [$l getDefaultAntennaRule]; set car($ln) [$r getCAR]; $r setCAR 0
    }
    # QB43_ANT_THREADS <n>: thread count for the repair only (r43_a: repair_antennas SEGFAULT with 16 threads in
    # grt::RepairAntennas::makeNetWires -> tmg_conn::loadWire -> dbBox::isOct, a parallel wire build)
    if {[qb_env QB43_ANT_THREADS ""] ne ""} { set_thread_count [qb_env QB43_ANT_THREADS ""] }
    set rc [catch { repair_antennas [lindex $::QC_PNR_DIODE 0] -iterations [qb_env QB43_ANT_ITER 3] -ratio_margin [qb_env QB43_ANT_MARGIN 25] } e]
    if {[qb_env QB43_ANT_THREADS ""] ne ""} { set_thread_count [qc_env QC_PNR_THREADS 16] }
    foreach ln [array names car] { [[[[ord::get_db] getTech] findLayer $ln] getDefaultAntennaRule] setCAR $car($ln) }
    set nd 0; foreach i [[ord::get_db_block] getInsts] { if {[[$i getMaster] getName] eq [lindex $::QC_PNR_DIODE 0]} { incr nd } }
    qc_summary "r43 grt antenna repair rc $rc diodes $nd [expr {[clock seconds] - $t}] s $e"
}
