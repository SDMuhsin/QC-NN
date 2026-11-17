# PRE_ROUTE_TCL part of impl/r14/top14.cfg (QB14_BAL 1): insertion-aware balancing of the R14 top clock (cts14.tcl
# skeleton + TritonCTS leaves).  Effective arrival per group (clk14.tcl: pin arrival + block insertion; top flops:
# median of a sample) -> target T = max over groups; every group whose median is earlier than T - QB14_TOL [0.04]
# gets a chain of QB14_DCELL [CKBD2] cells in front of its tap / leaf-root buffer (q14_C<c>, q14_H, q14_A, q14_L<g>),
# placed at the tap and legalised.  Two passes (pass 2 uses the per-cell delay measured in pass 1).  Writes
# rpt/clk14.txt (before / after).  q14_balance <passes> <placement|global_routing> <tag>: post_grt14.tcl re-runs one
# pass at GRT parasitics inside global_route -start_incremental / -end_incremental (QB14_BAL_GRT 1): the riser and
# spine run on M8 / M9 after GRT, which the M3 placement estimate cannot see.
source $::QB_R14/clk14.tcl
proc q14_balance {npass par tag} {
    set _rf $::OUT/rpt/clk14.txt
    set _tap [dict create hub q14_H act q14_A]
    for {set c 0} {$c < 8} {incr c} { dict set _tap col$c q14_C$c }
    foreach g {gap nw n0 n1 n2 n3} { dict set _tap $g q14_L$g; dict set _tap ${g}i q14_L${g}i }
    set _dc [qb_env QB14_DCELL CKBD2]; set _d [expr {[info exists ::Q14_DCELL_D] ? $::Q14_DCELL_D : 0.045}]; set _nins 0
    estimate_parasitics -$par   ;# (a route step started from cts.odb has no parasitics yet)
    q14_report $_rf "$tag (before balancing)"
    array set _ch {}
    for {set pass 1} {$pass <= $npass} {incr pass} {
        set T -1e9; foreach k [array names ::Q14_EFF] { set T [expr {max($T, $::Q14_EFF($k))}] }
        array set _before [array get ::Q14_EFF]
        set blk [ord::get_db_block]; set u [$blk getDefUnits]
        set log {}
        foreach k [lsort [array names ::Q14_EFF]] {
            if {![dict exists $_tap $k]} { continue }
            set pad [expr {$T - $::Q14_EFF($k)}]
            if {$pad < [qb_env QB14_TOL 0.04]} { continue }
            set n [expr {int(floor($pad / $_d + 0.5))}]
            if {$pass == 1 && ![info exists ::Q14_DCELL_D]} { set n [expr {int(floor(0.85 * $pad / $_d))}] }
            if {$n < 1} { continue }
            set ti [$blk findInst [dict get $_tap $k]]
            if {$ti eq "NULL"} { continue }
            set in [$ti findITerm I]; set drv [$in getNet]
            set loc [$ti getLocation]; set x [lindex $loc 0]; set y [lindex $loc 1]
            $in disconnect
            set prev $drv
            for {set j 0} {$j < $n} {incr j} {
                set nm q14_d${k}_${tag}${pass}_$j
                set i [odb::dbInst_create $blk [[ord::get_db] findMaster $_dc] $nm]
                $i setLocation [expr {$x + ($j % 20) * int(2.0 * $u)}] [expr {$y + ($j / 20) * int(1.8 * $u)}]; $i setPlacementStatus PLACED
                [$i findITerm I] connect $prev
                set nn [odb::dbNet_create $blk ${nm}_n]; $nn setSigType CLOCK
                [$i findITerm Z] connect $nn; set prev $nn
            }
            $in connect $prev
            incr _nins $n; set _ch($k) [expr {[info exists _ch($k)] ? $_ch($k) + $n : $n}]
            lappend log [format "%s +%d (pad %.3f)" $k $n $pad]
        }
        qc_log "r14 bal $tag pass $pass: T [format %.3f $T]; [join $log {, }]"
        detailed_placement {*}[p DPL_ARGS]
        if {$par eq "global_routing"} { global_route -end_incremental; global_route -start_incremental }
        estimate_parasitics -$par
        q14_report $_rf "$tag after balancing pass $pass"
        set dl {}
        foreach k [array names _ch] { if {$_ch($k) > 2 && [info exists _before($k)]} { lappend dl [expr {($::Q14_EFF($k) - $_before($k)) / $_ch($k)}] } }
        if {[llength $dl]} { set dl [lsort -real $dl]; set _d [expr {max(0.01, [lindex $dl [expr {[llength $dl] / 2}]])}]; set ::Q14_DCELL_D $_d; qc_log "r14 bal: measured [format %.3f $_d] ns per $_dc" }
        array unset _ch; array set _ch {}
    }
    qc_log "r14 bal $tag: $_nins delay cells inserted"
}
if {[qb_env QB14_BAL 1] && ![info exists ::Q14_BAL_DEFONLY]} {
    catch { file delete $::OUT/rpt/clk14.txt }
    q14_balance [qb_env QB14_BAL_PASS 2] placement pl
    check_placement
}
