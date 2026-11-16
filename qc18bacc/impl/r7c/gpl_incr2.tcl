# PRE_PLACE_TCL of act.cfg (results/r7c.md): impl/pnr/gpl_incr.tcl (incremental global placement after the place
# step's DRV repair, then a second DRV repair) with
#   * the incremental density = max(PLACE_DENSITY + 0.06, utilisation after the repair + QB7_INC_MARGIN (0.07)),
#     capped at 0.95 (gpl_incr.tcl's fixed PLACE_DENSITY + 0.06 stops with GPL-0302 when the repair raises the
#     utilisation above it: r7c_A2 / B2 / C2, +48 / +59 / +75 % cell area)
#   * the DRV-violating nets before the repair, by RTL class (line buffers, S1, S2, act pipe, selects, other), and the
#     cell area per repair -> rpt/r7c_drv.txt and summary.txt
proc qb7_cls {n} {
    foreach {re c} {{u_lb/} lb {lbf\[} lb_out {u_s1/} s1 {u_s2/} s2 {g_pipe_|actp_|act_q|act\[} act_pipe
                    {sel1|sel2} sel {g_ctx_} ctx_ctl {sdq|s_q} sdq {rdq|m_q} rdq} {
        if {[regexp $re $n]} { return $c }
    }
    return other
}
proc qb7_drv_classes {tag} {
    set blk [ord::get_db_block]
    set rf $::OUT/rpt/r7c_drv.tmp
    qc_to $rf { report_check_types -max_slew -max_capacitance -max_fanout -violators }
    array set v {}; array set c {}
    set f [open $rf]
    while {[gets $f line] >= 0} {
        if {![string match *VIOLATED* $line]} { continue }
        set pin [lindex $line 0]; set k [string last / $pin]
        set it NULL
        if {$k < 0} { set it [$blk findBTerm $pin] } elseif {[set i [$blk findInst [string range $pin 0 [expr {$k - 1}]]]] ne "NULL"} {
            set it [$i findITerm [string range $pin [expr {$k + 1}] end]] }
        if {$it ne "NULL" && [$it getNet] ne "NULL"} { set v([[$it getNet] getName]) 1 }
    }
    close $f; file delete $rf
    foreach n [array names v] { incr c([qb7_cls $n]) }
    set s "$tag drv_nets [array size v]:"
    foreach k [lsort [array names c]] { append s " $k $c($k)" }
    set fh [open $::OUT/rpt/r7c_drv.txt a]; puts $fh "$s [qc_util]"; close $fh
    qc_summary $s
}
if {[info commands qb_drv_orig] eq ""} {
    rename qc_repair_drv qb_drv_orig
    proc qc_repair_drv {} {
        qb7_drv_classes before_repair1
        qb_drv_orig
        qc_summary "r7c after_repair1 [qc_util]"
        if {![qb_env QB7_INC 1]} { return }
        regexp {utilisation ([0-9.]+)} [qc_util] -> u
        set dens [expr {min(0.95, max([p PLACE_DENSITY] + 0.06, $u + [qb_env QB7_INC_MARGIN 0.07]))}]
        qc_log "gpl_incr2: incremental global placement after the DRV repair, density $dens [qc_util]"
        global_placement -incremental -density $dens -pad_left [p PLACE_PAD] -pad_right [p PLACE_PAD] {*}[p GPL_ARGS]
        estimate_parasitics -placement
        qb7_drv_classes before_repair2
        qb_drv_orig
        qc_summary "r7c after_repair2 [qc_util]"
    }
}
