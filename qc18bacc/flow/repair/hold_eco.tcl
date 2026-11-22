# R35 opt-in post-route hold repair (results/r35.md), run in a routed run dir (common/or.sh <tag> hold35.tcl <log>):
#   1. db/<QB35_HDB [route_dr]> + its SDC (+ QB35_IO_TCL IO budget at QB35_IOL), propagated clock, corners QB35_CORNERS
#      [tt ss] with routed parasitics out/<top>_<c>_or.spef (OpenROAD copies, def2spef QC_SPEF_ORFIX 1, hold_eco.sh)
#   2. max-transition / max-cap repair (repair/drv.tcl) at the sign-off limits on every corner (R50), then repair_timing
#      -hold -hold_margin QB35_HOLD_M [0.05] (all paths incl. IO; setup kept by repair_timing's own check)
#   3. (fillers are removed before step 2) detailed_placement (incremental), every net of a new buffer or of a moved cell loses its wires
#   4. pin access of the old route dropped (route/pa_reset.tcl), global_route (-allow_congestion) and detailed_route
#      (QB35_HDR_ITER [64]) of every net (kit min-step / EOL rules route/drc_rules.tcl), fillers back, db/route_dr (old
#      one kept as route_dr_prehold), route, finish
# QB35_HOLD_DRY 1: steps 1-2 only (report what the repair would do, nothing saved).
# QB50_MPA 1 (R50, opt-in): outward planar access points for small macro pins (route/macro_pin_ap.tcl, results/r50.md
#   sec. 3c).  DRT keeps the design of a pin_access call in memory, so step 4 splits: this process (QB50_MPA_PASS [pa])
#   ends after global route with pin_access + the edit, saved as db/hold_mpa; hold_eco.sh then runs this script again
#   with QB50_MPA_PASS=dr (db/hold_mpa, route_hold.guide, detailed_route -no_pin_access, the same saves).
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
# R50: the repair session times tt AND ss (sign-off corners), so the DRV repair sees the ss slews itself (r48_col: OR-clean
# at tt 0.33 ns left 414 ss transition violators, ss / tt slew ratio 1.69-1.86, results/r48.md)
set ::QC_CORNERS [qb_env QB35_CORNERS {tt ss}]
set_thread_count [qc_env QB35_THREADS [qc_env QC_PNR_THREADS 16]]
set ::STEPS {init floorplan pdn place cts route finish}
proc h35_fill {} {
    set fill {}
    if {[p DCAP]} { set fill [concat $fill $::QC_PNR_DCAP] }
    if {[p FILL]} { set fill [concat $fill $::QC_PNR_FILL] }
    return $fill
}
# step 4 from detailed_route on (args: extra detailed_route options)
proc h35_dr {args} {
    set fill [h35_fill]
    set t [clock seconds]
    detailed_route -output_drc $::OUT/rpt/drt_hold.drc.rpt -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
        -droute_end_iter [qc_env QB35_HDR_ITER 64] -drc_report_iter_step 1 -verbose 1 {*}$args
    puts "R35_HOLD detailed_route [expr {[clock seconds] - $t}] s"
    set nv 0; catch { set g [open $::OUT/rpt/drt_hold.drc.rpt]; set nv [regexp -all {violation type} [read $g]]; close $g }
    puts "R35_HOLD drc_violations $nv"
    file copy -force $::OUT/db/route_dr.odb $::OUT/db/route_dr_prehold.odb
    qc_save route_dr
    if {[llength $fill] && ![qc_env QB35_FILL_BEFORE 0]} { filler_placement $fill }
    qc_save route
    source $::env(QC_FLOW)/pnr/or/finish.tcl
    qc_save finish
    puts "R35_HOLD saved route_dr / route / finish ([expr {[clock seconds] - $::T0}] s)"
    exit
}
if {[qc_env QB50_MPA 0] && [qc_env QB50_MPA_PASS pa] eq "dr"} {
    qc_load hold_mpa
    set_propagated_clock [all_clocks]
    set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
    read_guides $::OUT/route_hold.guide
    source $::QBF/route/drc_rules.tcl
    h35_dr -no_pin_access
}
set _db [qc_env QB35_HDB route_dr]
qc_load $_db
set_propagated_clock [all_clocks]
set top [p TOP]
foreach c $::QC_CORNERS { read_spef -corner $c $::OUT/out/${top}_${c}_or.spef }
# QB35_IO_TCL: re-apply the block IO budget at the insertion delay QB35_IOL, so the repair sees the IO hold windows
# PrimeTime checks (the db SDC carries the post-CTS L).  Default: the PrimeTime tt p50 clock-pin latency of this routed
# state (<run>/out/clk_lat_tt.txt, signoff/pt/common.tcl qb_pt_lat; R50: OpenSTA's pin arrival property is the worst over
# the loaded corners, so with ss loaded cts/clk_lat.tcl would return the ss latency).  Single-corner session: measured
# here (cts/clk_lat.tcl).
if {[qc_env QB35_IO_TCL ""] ne ""} {
    if {[qc_env QB35_IOL] eq ""} {
        set _lf $::OUT/out/clk_lat_tt.txt
        if {[llength $::QC_CORNERS] > 1} {
            if {![file exists $_lf] || [file mtime $_lf] < [file mtime $::OUT/out/$top.def]} { error "R35_HOLD $_lf missing or older than out/$top.def: run the block's post step first" }
            set _f [open $_lf]; set ::env(QB35_IOL) [lindex [read $_f] 0]; close $_f
        } else { source $::QBF/cts/clk_lat.tcl; set ::env(QB35_IOL) [qb_clk_lat hold_routed] }
    }
    # several corners: the hook's constant L becomes each corner's own clock latency (repair/io_ref.tcl)
    if {[llength $::QC_CORNERS] > 1} { source $::QBF/repair/io_ref.tcl; qb_io_ref $::env(QB35_IOL) $::env(QB35_IO_TCL) } \
    else { source $::env(QB35_IO_TCL) }
}
set blk [ord::get_db_block]
# fillers out BEFORE every change (PT ECO, hook, repairs) (by the filler_placement name prefix: the kit's DCAP and FILL masters are CORE cells, so
# remove_fillers leaves them and the resizer counts them as design area).  With them in place the resizer's utilization is
# 100 % of the core and repair_timing -hold stops at once with RSZ-0050 as soon as its -max_utilization cap is live (r48_act,
# results/r50.md: cells 63.4 % + fillers 36.6 %).
set fill [h35_fill]
set nf 0; foreach i [$blk getInsts] { if {[string match FILLER_* [$i getName]]} { odb::dbInst_destroy $i; incr nf } }
puts "R35_HOLD fillers removed $nf"
# QB35_ECO_TCL: PrimeTime DRV ECO change files (signoff/pt/drv_eco.tcl; R48) applied before the repair, in file order:
# "size_cell {inst} {cell}" (replace_cell) and "insert_buffer [get_pins|get_ports {p ...}] <cell> -new_net_names {n}
# -new_cell_names {c}" (p a driver pin or an input port: the buffer drives all its loads; p load pins: the buffer drives
# those).
proc r48_pin {name} {
    set k [string last / $name]
    if {$k < 0} { return [list bterm [[ord::get_db_block] findBTerm $name]] }
    set i [[ord::get_db_block] findInst [string range $name 0 [expr {$k - 1}]]]
    if {$i eq "NULL"} { return {iterm NULL} }
    return [list iterm [$i findITerm [string range $name [expr {$k + 1}] end]]]
}
proc r48_insbuf {pins cell nn cn} {
    set blk [ord::get_db_block]; set m [[ord::get_db] findMaster $cell]
    lassign [r48_pin [lindex $pins 0]] k0 p0
    if {$m eq "NULL" || $p0 eq "NULL" || [$p0 getNet] eq "NULL"} { return 0 }
    set net [$p0 getNet]
    if {$k0 eq "iterm" && [$p0 isOutputSignal]} {
        set loads {}; foreach it [$net getITerms] { if {$it ne $p0} { lappend loads [list iterm $it] } }
        foreach bt [$net getBTerms] { lappend loads [list bterm $bt] }
        lassign [[$p0 getInst] getLocation] x y
    } elseif {$k0 eq "bterm" && [$p0 getIoType] eq "INPUT"} {
        # input port: the buffer sits at the port and drives every load of the port net
        set loads {}; foreach it [$net getITerms] { lappend loads [list iterm $it] }
        set bb [$p0 getBBox]; set x [$bb xMin]; set y [$bb yMin]
    } else {
        set loads {}; set sx 0; set sy 0
        foreach p $pins { lassign [r48_pin $p] k o; if {$o eq "NULL"} { return 0 }; lappend loads [list $k $o]
            if {$k eq "iterm"} { lassign [[$o getInst] getLocation] a b; set sx [expr {$sx + $a}]; set sy [expr {$sy + $b}] } }
        set x [expr {round($sx / [llength $loads])}]; set y [expr {round($sy / [llength $loads])}]
    }
    set b [odb::dbInst_create $blk $m $cn]; $b setLocation $x $y; $b setPlacementStatus PLACED
    set n2 [odb::dbNet_create $blk $nn]; $n2 setSigType SIGNAL
    foreach l $loads { lassign $l k o; $o disconnect; $o connect $n2 }
    [$b findITerm I] connect $net; [$b findITerm Z] connect $n2
    return 1
}
if {[qc_env QB35_ECO_TCL ""] ne ""} {
    set _n 0; set _nb 0; set _miss 0
    foreach _ef $::env(QB35_ECO_TCL) {
        set _f [open $_ef]
        while {[gets $_f _l] >= 0} {
            set _l [string map {"\\/" "/"} $_l]
            if {[regexp {^size_cell \{(.*)\} \{(.*)\}\s*$} $_l -> _in _cn]} {
                set _i [[ord::get_db_block] findInst $_in]
                # replace_cell refuses masters OpenSTA does not see as equivalent (MAOI222D1 -> MAOI222D2, AOI211D1 ->
                # AOI211XD2: same pins; r48_col 278, r48_act 49 cells), but the odb master is already swapped when it raises
                # STA-1000: odb and STA then disagree and the cell's pins fall outside every route guide (r48_act
                # u_act/u_s1/u_b12/U2673: DRT-0218, results/r48.md).  Such sizes are skipped, the odb master is swapped back.
                if {$_i eq "NULL"} { incr _miss; continue }
                set _m0 [$_i getMaster]
                if {[catch { replace_cell $_in $_cn }]} {
                    if {[$_i getMaster] ne $_m0} { catch { $_i swapMaster $_m0 } }
                    if {[[$_i getMaster] getName] ne [$_m0 getName]} { puts "R48_ECO ERROR $_in left as [[$_i getMaster] getName]" }
                    incr _miss; continue
                }
                incr _n
            } elseif {[regexp {^insert_buffer \[get_(?:pins|ports) \{(.*)\}\] (\S+) -new_net_names \{(\S+)\} -new_cell_names \{(\S+)\}} $_l -> _ps _cn _nn _bn]} {
                if {[r48_insbuf $_ps $_cn $_nn $_bn]} { incr _nb } else { incr _miss }
            }
        }
        close $_f
    }
    puts "R48_ECO size_cell $_n insert_buffer $_nb missing $_miss ($::env(QB35_ECO_TCL))"
}
# R37 opt-in QB37_HPRE_TCL: a hook before the repair (hub: repair/hub_setup_pre.tcl)
if {[qc_env QB37_HPRE_TCL ""] ne ""} { source $::env(QB37_HPRE_TCL) }
proc h35 {tag} {
    # worst slacks first: they build the timing graph; endpoint_violation_count before that segfaults (null graph, R50)
    set w {}; foreach c $::QC_CORNERS { lappend w [format "%s %.3f / %.3f" $c [expr {[sta::worst_slack_corner [sta::find_corner $c] max]*1e9}] [expr {[sta::worst_slack_corner [sta::find_corner $c] min]*1e9}]] }
    set ns NA; set nh NA; catch { set ns [sta::endpoint_violation_count max] }; catch { set nh [sta::endpoint_violation_count min] }
    puts "R35_HOLD $tag setup / hold wns [join $w {, }]; violating endpoints (all corners) setup $ns hold $nh"
}
h35 before
array set old {}; foreach i [$blk getInsts] { set old([$i getName]) [$i getLocation] }
# DRV repair first (repair/drv.tcl), then hold: DRV buffers / resizes after the hold repair re-broke hold (r48_act try 4)
# sign-off DRV limits, no margin, when ss is loaded: design max transition min(0.5, 0.1 P) at the sign-off period
# QB35_PER (common/constraints.sdc; the libraries' own limits apply as well) and the PrimeTime pin capacitance (P&R liberty,
# common/qb.tcl) without a cap margin
source $::QBF/repair/drv.tcl
if {[llength $::QC_CORNERS] > 1} {
    set ::env(QB_DRV_SLEW) [expr {min(0.5, 0.1 * [qc_env QB35_PER 6.5])}]; set ::env(QB_DRV_CAPM) 0
}
qb_drv hold_routed
puts [format "R35_HOLD resizer utilization %.4f (cap %s %%)" [rsz::utilization] [qc_env QB35_MAXU 95]]
set t [clock seconds]
if {[catch { repair_timing -hold -hold_margin [qc_env QB35_HOLD_M 0.05] -max_buffer_percent [qc_env QB35_HOLD_PCT 20] \
        -max_utilization [qc_env QB35_MAXU 95] } e]} { puts "R35_HOLD repair stopped: $e" }
puts "R35_HOLD repair_timing -hold [expr {[clock seconds] - $t}] s"
set new {}; foreach i [$blk getInsts] { if {![info exists old([$i getName])]} { lappend new $i } }
puts "R35_HOLD new_insts [llength $new]"
h35 after_repair_unlegal
# R37 opt-in QB37_FORCE_SAVE 1: continue without new hold cells (the QB37_HPRE_TCL hook made the change, e.g. a resize)
if {[qc_env QB35_HOLD_DRY 0] || ([llength $new] == 0 && ![qc_env QB37_FORCE_SAVE 0])} { puts "R35_HOLD done (no save)"; exit }
# legalisation of every cell (new and resized cells push neighbours), then a full re-route: DRT on top of kept routing
# breaks nets whose old wires do not match the new guides (r35_col: 'pin not visited' / checkConnectivity break on act_o
# feedthroughs; the R37 incremental mode QB35_HDR_FULL 0 / QB37_FIRM / QB37_RIP_* was removed in R50, git history)
detailed_placement {*}[p DPL_ARGS]
if {[catch {check_placement} e]} { puts "R35_HOLD check_placement: $e" }
set nmov 0; foreach i [$blk getInsts] { if {[info exists old([$i getName])] && $old([$i getName]) ne [$i getLocation]} { incr nmov } }
set nr 0; foreach n [$blk getNets] { if {[$n isSpecial]} continue; set w [$n getWire]; if {$w ne "NULL"} { odb::dbWire_destroy $w; incr nr } }
puts "R35_HOLD moved_insts $nmov nets_ripped $nr"
set_routing_layers -signal $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER -clock $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER
set_global_routing_layer_adjustment $::QC_PNR_MIN_LAYER-$::QC_PNR_MAX_LAYER [p GR_ADJUST]
foreach {l a} [qc_env QB15_GADJ_L ""] { set_global_routing_layer_adjustment $l $a }
# stale DRT pin access of the loaded routed db out, so GRT sees the resized / moved / new cells' real pins (R49 DRT-0218)
source $::QBF/route/pa_reset.tcl
set t [clock seconds]
global_route -guide_file $::OUT/route_hold.guide -allow_congestion -congestion_iterations 10
puts "R35_HOLD global_route [expr {[clock seconds] - $t}] s"
estimate_parasitics -global_routing
h35 after_legal_grt_est
# R37 opt-in QB37_HPOST_TCL: more hold rounds at global-route parasitics (impl/r37/hpost37.tcl; results/r37.md)
if {[qc_env QB37_HPOST_TCL ""] ne ""} { source $::env(QB37_HPOST_TCL) }
if {[llength $fill] && [qc_env QB35_FILL_BEFORE 0]} { filler_placement $fill }
source $::QBF/route/drc_rules.tcl
if {[qc_env QB50_MPA 0]} {
    pin_access -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER
    source $::QBF/route/macro_pin_ap.tcl
    qb_macro_pin_ap
    qc_save hold_mpa
    puts "R35_HOLD mpa saved db/hold_mpa ([expr {[clock seconds] - $::T0}] s)"
    exit
}
h35_dr
