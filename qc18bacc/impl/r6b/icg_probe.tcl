# impl/r6b: clock-gate (ICG) and area probe of a chip checkpoint (results/r6b.md), read-only, in parallel with the flow:
#   cd <run> && QC_FLOW=<repo>/flow/tsmc65 QC_PNR_OUT=$PWD QB_FROM=cts|cts_rt|route_dr openroad -exit icg_probe.tcl
# 1. every ICG (CKLN*): output slew (tt, placement or global-route parasitics), fanout, histogram, 15 worst
# 2. the R6b post-CTS worst path from u_top/g_r3b_u_prm/stg_t_reg_441_ (launch latency, ICG stage) -> rpt/icg_<db>.rpt
# 3. area split: die, column blocks, macros, top std cells = DC logic / repair buffers / CTS / ICG, phys, white space
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QB_THREADS 3]
set ::STEPS {init floorplan pdn place cts route finish}
set s [qc_env QB_FROM cts]
qc_read_liberty
read_db $::OUT/db/$s.odb
read_sdc $::OUT/db/[expr {[file exists $::OUT/db/$s.sdc] ? $s : "cts"}].sdc
qc_set_rc
set_propagated_clock [all_clocks]
if {[qc_env QB_PAR placement] eq "grt"} { estimate_parasitics -global_routing } else { estimate_parasitics -placement }
set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
if {[qc_env QB_TOP5 0]} {
    # only: 5 worst endpoints (one path each) -> rpt/top5_<db>.rpt
    qc_to $::OUT/rpt/top5_$s.rpt { report_checks -path_delay max -group_count 5 -endpoint_count 1 -format full_clock_expanded -digits 3 }
    exit
}
# ---- ICGs
set l {}; set h {0 0 0 0 0}
foreach i [$blk getInsts] {
    set m [[$i getMaster] getName]
    if {![regexp {^CKL} $m]} continue
    set q ""
    foreach t [$i getITerms] { if {[$t isOutputSignal]} { set q $t } }
    if {$q eq ""} continue
    set pn "[$i getName]/[[$q getMTerm] getName]"
    set sl 0.0; catch { set sl [get_property [get_pins $pn] slew_max] }
    set fo 0; set n [$q getNet]; if {$n ne "NULL"} { set fo [expr {[llength [$n getITerms]] - 1}] }
    lappend l [list $pn $m $sl $fo]
    set b [expr {$sl > 1.0 ? 4 : $sl > 0.5 ? 3 : $sl > 0.3 ? 2 : $sl > 0.15 ? 1 : 0}]
    lset h $b [expr {[lindex $h $b] + 1}]
}
puts "ICG db $s n [llength $l] slew_hist <=0.15 [lindex $h 0] 0.15-0.3 [lindex $h 1] 0.3-0.5 [lindex $h 2] 0.5-1.0 [lindex $h 3] >1.0 [lindex $h 4]"
foreach e [lrange [lsort -real -decreasing -index 2 $l] 0 14] { puts [format "ICG_WORST %s %s slew %.3f fanout %d" {*}$e] }
array set mm {}; foreach e $l { set k [lindex $e 1]; if {[info exists mm($k)]} { incr mm($k) } else { set mm($k) 1 } }
puts "ICG masters [array get mm]"
# ---- the named path
qc_to $::OUT/rpt/icg_$s.rpt {
    report_checks -path_delay max -from [get_pins u_top/g_r3b_u_prm/stg_t_reg_441_/CP] -format full_clock_expanded -fields {slew cap fanout} -digits 3
    report_checks -path_delay max -format full_clock_expanded -fields {slew cap fanout} -digits 3
    report_clock_skew -setup
}
puts "WNS tt [format %.3f [expr {[sta::worst_slack_corner [sta::find_corner tt] max] * 1e9}]] viol [sta::endpoint_violation_count max]"
# ---- area
set die [$blk getDieArea]; set dA [expr {[$die dx] / $u * [$die dy] / $u}]
array set a {blk 0 mac 0 dc 0 rbuf 0 cts 0 icg 0 phys 0}; array set cnt {blk 0 mac 0 dc 0 rbuf 0 cts 0 icg 0 phys 0}
foreach i [$blk getInsts] {
    set m [$i getMaster]; set ar [expr {[$m getWidth] / $u * [$m getHeight] / $u}]
    set mn [$m getName]; set nm [$i getName]
    if {$mn eq "qb_col_blk"} { set k blk } elseif {[$m isBlock]} { set k mac
    } elseif {[regexp {^(FILL|DCAP|TAP|BOUNDARY|ANTENNA|GFILL)} $mn] || [$m getType] ne "CORE"} { set k phys
    } elseif {[regexp {^CKL} $mn]} { set k icg
    } elseif {[regexp {^(clkbuf|clkload|cts|delaybuf)} $nm]} { set k cts
    } elseif {[regexp {^(wire|fanout|max_length|load_slew|max_cap|split|rebuffer|hold|input|output|gain|buffer|clone|place|rsz)[0-9_]} $nm]} { set k rbuf
    } else { set k dc }
    set a($k) [expr {$a($k) + $ar}]; incr cnt($k)
}
puts [format "AREA db %s die_mm2 %.3f (%.1f x %.1f um)" $s [expr {$dA / 1e6}] [expr {[$die dx] / $u}] [expr {[$die dy] / $u}]]
set tot 0
foreach k {blk mac dc icg rbuf cts phys} {
    puts [format "AREA %s_mm2 %.3f n %d" $k [expr {$a($k) / 1e6}] $cnt($k)]; set tot [expr {$tot + $a($k)}]
}
puts [format "AREA white_mm2 %.3f (die - all instances, incl. halos / channels)" [expr {($dA - $tot) / 1e6}]]
puts "ICG_PROBE done [expr {[clock seconds] - $::T0}] s"
exit
