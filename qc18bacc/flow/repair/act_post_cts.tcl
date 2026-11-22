# PRE_ROUTE_TCL of blocks/act/act.cfg (blocks/act/run.sh postcts: flow route step from db/cts.odb): post-CTS re-spread
# (R16, results/r16.md), then the post-CTS setup / hold repair repair/post_cts.tcl, db/cts_rt.odb and the end of the run (the
# route runs as blocks/act/run.sh route, route/act_route.tcl: the flow's own GRT stalled on this block, r9a_f2r).
# Re-spread mechanism (results/r13.md sec. 2): gpl spreads to the target density, but DRV repair 2 + CTS + hold buffers
# (+0.16 mm2) are only legalised in place, and gpl never sees the per-instance S1 DPL padding -> S1 AOI22 clusters at local
# util 0.83-0.86, ~1 signal pin / um2 -> M2 shorts.  Here, on the CTS checkpoint (all clock buffers present):
#   1. cell dump rpt/r16_cells_pre.txt (cell_dump.tcl format, for m2_short.py '-' = pin-density deciles)
#   2. act edge chains FIRM (place/act_edge.tcl qb9_chain from every act[] port: they sit at their pins), clock tree FIRM
#   3. global_placement -incremental -timing_driven at density utilisation + 0.05, no gpl padding, S1 cells temporarily
#      swapped to the next drive strength whose footprint is >= width + 2 sites (gpl then reserves the DPL padding where
#      the S1 cells are), -init_density_penalty 0.01 (gpl default 8e-5: incremental gpl first collapses to overflow 0.8 and
#      re-spreads, which re-places the repair buffers and costs +0.10 mm2 of new DRV repair, r16_sa / sb), -overflow 0.05
#   4. DRV repair of the nets the move made violating, S1 DPL padding, detailed placement
#   5. cell dump rpt/r16_cells_post.txt
#   6. S1 DPL padding again, repair/post_cts.tcl (IO budget shifted by QB_IO_LAT, QB_RT_LOOPS), stop after db/cts_rt.odb
proc qb16_dump {fn} {
    set blk [ord::get_db_block]; set dbu [$blk getDbUnitsPerMicron]
    set f [open $fn w]
    foreach i [$blk getInsts] {
        set n 0
        foreach it [$i getITerms] { set nt [$it getNet]; if {$nt ne "NULL" && [$nt getSigType] eq "SIGNAL"} { incr n } }
        set b [$i getBBox]
        puts $f [format "%s %.2f %.2f %.2f %.2f %d %s" [[$i getMaster] getName] [expr {[$b xMin] / double($dbu)}] \
            [expr {[$b yMin] / double($dbu)}] [expr {[$b xMax] / double($dbu)}] [expr {[$b yMax] / double($dbu)}] $n [$i getName]]
    }
    close $f
}
set _t [clock seconds]
qb16_dump $::OUT/rpt/r16_cells_pre.txt
source $::QBF/place/act_edge.tcl
set _blk [ord::get_db_block]; set ::QB9_EDGE {}
foreach _bt [$_blk getBTerms] {
    if {![regexp {^act\[\d+\]$} [$_bt getName]]} { continue }
    foreach _i [qb9_chain $_bt] { lappend ::QB9_EDGE [$_i getName] }
}
# the clock tree stays where CTS put it (r16_sc: gpl moved the top CTS buffers, clkbuf_0 -> clkbuf_1 wire 0.39 ns,
# act edge flops' latency 0.98 vs the 0.55 budget, reg2act -0.338): CTS buffers / ICGs FIRM with the edge chains
set _nck 0
foreach _i [$_blk getInsts] {
    if {[regexp {^(clkbuf|clkload|delaybuf)} [$_i getName]] || [regexp {^CKL[NH]} [[$_i getMaster] getName]]} {
        lappend ::QB9_EDGE [$_i getName]; incr _nck
    }
}
regexp {utilisation ([0-9.]+)} [qc_util] -> _u
set _d [expr {$_u + 0.05}]
set _gp 0
qc_summary "r16 respread pre [qc_util] fixed_cells [llength $::QB9_EDGE] (clock $_nck) density $_d gpl_pad $_gp"
# S1 cells (u_act/u_s1/*) swapped to the next drive strength of the same function whose footprint is >= width + 2 sites
# (gpl then reserves the DPL padding where the S1 cells are), swapped back right after gpl
set _sw {}
set _db [ord::get_db]; set _site [[lindex [$_blk getRows] 0] getSite]; set _sw0 [$_site getWidth]
array set _big {}
foreach _i [$_blk getInsts] {
    if {![string match u_act/u_s1/* [$_i getName]]} { continue }
    set _m [$_i getMaster]; set _mn [$_m getName]
    if {![info exists _big($_mn)]} {
        set _big($_mn) NULL
        if {[regexp {^(.*D)(\d+)(.*)$} $_mn -> _a _k _z]} {
            foreach _k2 {1 2 3 4 6 8} {
                if {$_k2 <= $_k} { continue }
                set _m2 [$_db findMaster "$_a$_k2$_z"]
                if {$_m2 ne "NULL" && [$_m2 getWidth] >= [$_m getWidth] + 2 * $_sw0} { set _big($_mn) $_m2; break }
            }
        }
    }
    if {$_big($_mn) ne "NULL" && ![catch {$_i swapMaster $_big($_mn)} _ok] && $_ok} { lappend _sw [list $_i $_m] } elseif {$_big($_mn) ne "NULL"} { set _big($_mn) NULL }
}
qc_summary "r16 respread s1_inflated [llength $_sw]"
estimate_parasitics -placement
global_placement -incremental -timing_driven -density $_d -pad_left $_gp -pad_right $_gp -init_density_penalty 0.01 -overflow 0.05
foreach _p $_sw { [lindex $_p 0] swapMaster [lindex $_p 1] }
estimate_parasitics -placement
set _ndrv [expr {[sta::max_slew_violation_count] + [sta::max_capacitance_violation_count] + [sta::max_fanout_violation_count]}]
qc_summary "r16 respread drv_after_gpl $_ndrv"
# the flow's qc_repair_drv (DRV nets only), not place/act_place.tcl's wrapper (its extra incremental gpl at default density
# penalty collapses and re-spreads the placement again: r16_sa / r16_sb)
if {$_ndrv > 0} { qc_repair_drv }
qb13_pad
detailed_placement {*}[p DPL_ARGS]
check_placement
estimate_parasitics -placement
qb16_dump $::OUT/rpt/r16_cells_post.txt
qc_summary "r16 respread post [qc_util] [join [qc_timing_lines respread] { | }] wall_s [expr {[clock seconds] - $_t}]"
# ---- post-CTS repair (S1 padding again before its detailed placements), checkpoint db/cts_rt.odb, end of the run
qb13_pad
source $::QBF/repair/post_cts.tcl
qc_log "r13 stop after post-CTS repair (db/cts_rt.odb)"; exit 0
