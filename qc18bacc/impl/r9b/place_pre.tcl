# PRE_PLACE_TCL of impl/r9b/hub.cfg: impl/r5b/pre_place.tcl (max transition 0.4, remove_buffers, incremental gpl + 2nd
# DRV repair) plus two opt-in R9b items:
#   QB9_PINPAD n   placement padding of n sites left / right on every cell with a pin on a net that also reaches a
#                  block port (the cells pulled onto the fixed north-edge pins: column f_y / b2 / w_y receivers, s_rd /
#                  pf / w_r drivers, act-port drivers), for gpl and DPL
#   QB9_DMAP 1     before the place step's detailed_placement: over-full 20-um bins of the global placement (cell area /
#                  free row area, macros + halo excluded) by region and by cell class -> rpt/dmap.txt; QB9_DMAP_STOP 1
#                  then saves db/place_gpl.odb and exits (diagnosis run)
source $::QB_R5B/pre_place.tcl
# QB9_CHBLK pct: partial placement blockages (max density pct %) over the channels between macro rows under the array
#   (r9b_g0 diagnosis: DPL-0036 cells = upsized glue drivers of the S-macro pins packed into the 27-um row-3 / row-4
#   channel, rpt/dpl_fail.txt) -> gpl spreads that logic into the band instead of filling the channels
# QB9_GPL2 1: an incremental gpl (density QB9_GPL2_DENS, default 0.80) + DRV repair after the place step's last DRV
#   repair (r9b_g0: 55 k um2 of repair buffers left in channels / halos, never re-spread)
if {[qb_env QB9_CHBLK 0] > 0} {
    set blk [ord::get_db_block]; set u [[ord::get_db_tech] getDbUnitsPerMicron]
    set rows {}
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isBlock]} continue
        set b [$i getBBox]; if {[$b xMin] < 840 * $u} continue
        lappend rows [list [$b yMin] [$b yMax] [$b xMin] [$b xMax]]
    }
    array set R {}
    foreach r $rows { lassign $r y0 y1 x0 x1; lappend R($y0) $r }
    set ys [lsort -integer [array names R]]; set nb 0
    for {set k 0} {$k < [llength $ys] - 1} {incr k} {
        set lo $R([lindex $ys $k]); set hi $R([lindex $ys [expr {$k + 1}]])
        set top [tcl::mathfunc::max {*}[lmap r $lo {lindex $r 1}]]; set bot [lindex $ys [expr {$k + 1}]]
        if {$bot - $top <= 0 || $bot - $top > 100 * $u} continue
        set xa [tcl::mathfunc::min {*}[lmap r [concat $lo $hi] {lindex $r 2}]]; set xb [tcl::mathfunc::max {*}[lmap r [concat $lo $hi] {lindex $r 3}]]
        set bk [odb::dbBlockage_create $blk $xa $top $xb $bot]
        $bk setMaxDensity [qb_env QB9_CHBLK 0]; incr nb
        qc_log [format "r9b: channel blockage %.1f-%.1f x %.1f-%.1f um max density %s %%" [expr {$xa / double($u)}] [expr {$xb / double($u)}] [expr {$top / double($u)}] [expr {$bot / double($u)}] [qb_env QB9_CHBLK 0]]
    }
}
if {[qb_env QB9_GPL2 0] && [info commands qb9_drv_prev] eq ""} {
    rename qc_repair_drv qb9_drv_prev
    proc qc_repair_drv {} {
        qb9_drv_prev
        set dens [qb_env QB9_GPL2_DENS 0.80]
        global_placement -incremental -density $dens -pad_left [p PLACE_PAD] -pad_right [p PLACE_PAD] {*}[p GPL_ARGS]
        estimate_parasitics -placement
        qc_log "r9b: incremental gpl after the last DRV repair, density $dens [qc_util]"
        qb_drv_orig
    }
}
proc qb9_cls {n} {
    set c [lindex [split $n /] 0]
    if {[regexp {^(wire|fanout|max_cap|split|rebuffer|load_slew|gain)\d} $c]} { return rsz }
    return [regsub -all {\d+} $c N]
}
if {[qb_env QB9_PINPAD 0] > 0} {
    set _pp {}
    foreach bt [[ord::get_db_block] getBTerms] {
        set net [$bt getNet]; if {$net eq "NULL" || [$bt getSigType] ne "SIGNAL" || [$bt getName] in {clk rst_n}} continue
        foreach it [$net getITerms] { lappend _pp [[$it getInst] getName] }
    }
    set _pp [lsort -unique $_pp]
    set _n [qb_env QB9_PINPAD 0]
    set_placement_padding -instances [get_cells $_pp] -left $_n -right $_n
    qc_log "r9b: placement padding $_n sites on [llength $_pp] port-attached cells"
}
proc qb9_dmap {} {
    set blk [ord::get_db_block]; set u [expr {double([[ord::get_db_tech] getDbUnitsPerMicron])}]
    set die [$blk getDieArea]; set W [expr {[$die xMax] / $u}]; set H [expr {[$die yMax] / $u}]
    set B 20.0; set nx [expr {int(ceil($W / $B))}]; set ny [expr {int(ceil($H / $B))}]
    set halo [lindex [p MACRO_HALO] 0]
    array set cap {}; array set use {}; array set cls {}
    for {set i 0} {$i < $nx} {incr i} { for {set j 0} {$j < $ny} {incr j} { set cap($i,$j) [expr {$B * $B}] } }
    foreach i [$blk getInsts] {
        if {![[$i getMaster] isBlock]} continue
        set b [$i getBBox]
        set x0 [expr {[$b xMin] / $u - $halo}]; set x1 [expr {[$b xMax] / $u + $halo}]
        set y0 [expr {[$b yMin] / $u - $halo}]; set y1 [expr {[$b yMax] / $u + $halo}]
        for {set ii [expr {max(0, int($x0 / $B))}]} {$ii <= min($nx - 1, int($x1 / $B))} {incr ii} {
            for {set jj [expr {max(0, int($y0 / $B))}]} {$jj <= min($ny - 1, int($y1 / $B))} {incr jj} {
                set ox [expr {max(0.0, min($x1, ($ii + 1) * $B) - max($x0, $ii * $B))}]
                set oy [expr {max(0.0, min($y1, ($jj + 1) * $B) - max($y0, $jj * $B))}]
                set cap($ii,$jj) [expr {max(0.0, $cap($ii,$jj) - $ox * $oy)}]
            }
        }
    }
    foreach i [$blk getInsts] {
        set m [$i getMaster]; if {[$m isBlock]} continue
        lassign [$i getLocation] x y
        set k "[expr {min($nx - 1, int($x / $u / $B))}],[expr {min($ny - 1, int($y / $u / $B))}]"
        set a [expr {[$m getWidth] * [$m getHeight] / $u / $u}]
        set use($k) [expr {([info exists use($k)] ? $use($k) : 0.0) + $a}]
        lappend cls($k) [qb9_cls [$i getName]] $a
    }
    set f [open $::OUT/rpt/dmap.txt w]
    array set reg {}; array set rcls {}; set nfull 0
    foreach k [array names use] {
        lassign [split $k ,] i j
        set c $cap($i,$j); set r [expr {$c > 1.0 ? $use($k) / $c : 99.0}]
        if {$r <= 0.95} continue
        incr nfull
        set yc [expr {($j + 0.5) * $B}]; set xc [expr {($i + 0.5) * $B}]
        set g [expr {$yc > $H - 60 ? "north_edge" : ($c < 0.9 * $B * $B ? "macro_channel/halo" : ($xc < 860 ? "west_strip" : "band"))}]
        set ov [expr {$use($k) - 0.95 * $c}]
        set reg($g) [expr {([info exists reg($g)] ? $reg($g) : 0.0) + $ov}]
        foreach {cc a} $cls($k) { set rcls($g,$cc) [expr {([info exists rcls($g,$cc)] ? $rcls($g,$cc) : 0.0) + $a}] }
        if {$r > 1.2} { puts $f [format "bin x %.0f y %.0f util %.2f free %.0f um2 region %s" $xc $yc $r $c $g] }
    }
    puts $f "# over-full (> 0.95) 20-um bins: $nfull"
    foreach g [array names reg] {
        puts $f [format "REGION %-20s excess %.0f um2" $g $reg($g)]
        set l {}; foreach k [array names rcls $g,*] { lappend l [list [lindex [split $k ,] 1] $rcls($k)] }
        foreach x [lrange [lsort -real -decreasing -index 1 $l] 0 7] { puts $f [format "   %-40s %.0f um2" {*}$x] }
    }
    close $f
    qc_log "r9b dmap: $nfull over-full bins ([join [lmap g [array names reg] {format "%s %.0f" $g $reg($g)}] {, }] um2 excess)"
}
if {[qb_env QB9_DMAP 0] && [info commands qb9_dpl_orig] eq ""} {
    rename detailed_placement qb9_dpl_orig
    proc detailed_placement {args} {
        if {![info exists ::qb9_dmap_done]} {
            set ::qb9_dmap_done 1
            qb9_dmap
            if {[qb_env QB9_DMAP_STOP 0]} { write_db $::OUT/db/place_gpl.odb; qc_log "r9b: dmap stop"; exit }
        }
        qb9_dpl_orig {*}$args
    }
}
