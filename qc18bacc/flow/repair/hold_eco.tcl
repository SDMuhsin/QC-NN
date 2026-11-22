# R35 opt-in post-route hold repair (results/r35.md), run in a routed run dir (common/or.sh <tag> hold35.tcl <log>):
#   1. db/<QB35_HDB [route_dr]> + its SDC (+ QB35_IO_TCL IO budget at QB35_IOL), propagated clock, routed parasitics read_spef out/<top>_tt.spef (OpenROAD copy;
#      def2spef with QC_SPEF_ORFIX 1)
#   2. max-transition / max-cap repair (repair/drv.tcl), then repair_timing -hold -hold_margin QB35_HOLD_M [0.05] (all paths
#      incl. IO; setup kept by repair_timing's own check)
#   3. fillers removed, detailed_placement (incremental), every net of a new buffer or of a moved cell loses its wires
#   4. pin access of the old route dropped (route/pa_reset.tcl), global_route (-allow_congestion) and detailed_route
#      (QB35_HDR_ITER [64]) of every net (QB35_HDR_FULL [1]; 0: only the touched nets, on top of the kept routing - fails
#      in this OpenROAD build, see below; kit min-step / EOL rules route/drc_rules.tcl), fillers back, db/route_dr (old
#      one kept as route_dr_prehold), route, finish
# QB35_HOLD_DRY 1: steps 1-2 only (report what the repair would do, nothing saved).
set ::T0 [clock seconds]
source $::env(QC_FLOW)/pnr/or/lib.tcl
set ::OUT $::env(QC_PNR_OUT)
source $::OUT/config.tcl
qc_config
set_thread_count [qc_env QB35_THREADS [qc_env QC_PNR_THREADS 16]]
set ::STEPS {init floorplan pdn place cts route finish}
set _db [qc_env QB35_HDB route_dr]
qc_load $_db
set_propagated_clock [all_clocks]
set top [p TOP]
set _sp [qc_env QB35_SPEF $::OUT/out/${top}_tt.spef]
read_spef $_sp
# QB35_IO_TCL: re-apply the block IO budget at the insertion delay QB35_IOL, by default measured here on the routed
# parasitics (cts/clk_lat.tcl, p50 clock-pin latency, the definition the PrimeTime sign-off uses per corner), so the
# repair sees the IO hold windows PrimeTime checks (the db SDC carries the post-CTS L)
source $::QBF/cts/clk_lat.tcl
if {[qc_env QB35_IOL] eq ""} { set ::env(QB35_IOL) [qb_clk_lat hold_routed] }
if {[qc_env QB35_IO_TCL ""] ne ""} { source $::env(QB35_IO_TCL) }
# QB35_ECO_TCL: PrimeTime DRV ECO change files (signoff/pt/drv_eco.tcl; R48) applied before the repair, in file order:
# "size_cell {inst} {cell}" (replace_cell) and "insert_buffer [get_pins|get_ports {p ...}] <cell> -new_net_names {n}
# -new_cell_names {c}" (p a driver pin or an input port: the buffer drives all its loads; p load pins: the buffer drives
# those).  Run with QB37_FIRM 0 (full re-route): with every old cell FIRM the upsized cells cannot be legalised (r48_col:
# DPL-0033, 10 overlaps, 165 unreachable buffer pins).
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
    lappend ::r37_newinst $b
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
                lappend ::r37_newinst $_i; incr _n
            } elseif {[regexp {^insert_buffer \[get_(?:pins|ports) \{(.*)\}\] (\S+) -new_net_names \{(\S+)\} -new_cell_names \{(\S+)\}} $_l -> _ps _cn _nn _bn]} {
                if {[r48_insbuf $_ps $_cn $_nn $_bn]} { incr _nb } else { incr _miss }
            }
        }
        close $_f
    }
    puts "R48_ECO size_cell $_n insert_buffer $_nb missing $_miss ($::env(QB35_ECO_TCL))"
}
# R37 opt-in QB37_HPRE_TCL: a hook before the repair (e.g. repair/act_hold_pre.tcl input-port buffers; results/r37.md)
if {[qc_env QB37_HPRE_TCL ""] ne ""} { source $::env(QB37_HPRE_TCL) }
proc h35 {tag} {
    set s [sta::worst_slack_corner [sta::find_corner tt] max]; set h [sta::worst_slack_corner [sta::find_corner tt] min]
    set ns NA; set nh NA; catch { set ns [sta::endpoint_violation_count max] }; catch { set nh [sta::endpoint_violation_count min] }
    puts [format "R35_HOLD %s setup_wns %.3f setup_viol %s hold_wns %.3f hold_viol %s" $tag [expr {$s*1e9}] $ns [expr {$h*1e9}] $nh]
}
h35 before
set blk [ord::get_db_block]
array set old {}; foreach i [$blk getInsts] { set old([$i getName]) [$i getLocation] }
# DRV repair first (repair/drv.tcl), then hold: DRV buffers / resizes after the hold repair re-broke hold (r48_act try 4)
source $::QBF/repair/drv.tcl
qb_drv hold_routed
set t [clock seconds]
if {[catch { repair_timing -hold -hold_margin [qc_env QB35_HOLD_M 0.05] -max_buffer_percent [qc_env QB35_HOLD_PCT 20] \
        -max_utilization [qc_env QB35_MAXU 95] } e]} { puts "R35_HOLD repair stopped: $e" }
puts "R35_HOLD repair_timing -hold [expr {[clock seconds] - $t}] s"
set new {}; foreach i [$blk getInsts] { if {![info exists old([$i getName])]} { lappend new $i } }
puts "R35_HOLD new_insts [llength $new]"
h35 after_repair_unlegal
# R37 opt-in QB37_FORCE_SAVE 1: continue without new hold cells (the QB37_HPRE_TCL hook made the change, e.g. a resize)
if {[qc_env QB35_HOLD_DRY 0] || ([llength $new] == 0 && ![qc_env QB37_FORCE_SAVE 0])} { puts "R35_HOLD done (no save)"; exit }
set fill {}
if {[p DCAP]} { set fill [concat $fill $::QC_PNR_DCAP] }
if {[p FILL]} { set fill [concat $fill $::QC_PNR_FILL] }
# fillers out (by the filler_placement name prefix: DCAP fillers are CORE cells, remove_fillers leaves them in place)
set nf 0; foreach i [$blk getInsts] { if {[string match FILLER_* [$i getName]]} { odb::dbInst_destroy $i; incr nf } }
puts "R35_HOLD fillers removed $nf"
# R37 opt-in QB37_FIRM 1: every cell that existed before the repair (except hook-created ones, ::r37_newinst) is FIRM
# during the legalisation, so only the new buffers move and no kept wire loses its pin (results/r37.md sec. 12)
set _firm {}
if {[qc_env QB37_FIRM 0]} {
    set _hk {}; if {[info exists ::r37_newinst]} { foreach i $::r37_newinst { dict set _hk [$i getName] 1 } }
    foreach i [$blk getInsts] { if {[info exists old([$i getName])] && ![dict exists $_hk [$i getName]] && [$i getPlacementStatus] eq "PLACED"} { $i setPlacementStatus FIRM; lappend _firm $i } }
    puts "R35_HOLD R37 firm cells [llength $_firm]"
}
detailed_placement {*}[p DPL_ARGS]
foreach i $_firm { $i setPlacementStatus PLACED }
if {[catch {check_placement} e]} { puts "R35_HOLD check_placement: $e" }
array set rip {}; set nmov 0; set _movd {}
foreach i $new { foreach it [$i getITerms] { set n [$it getNet]; if {$n ne "NULL"} { set rip([$n getName]) $n } } }
# R37: nets changed by the QB37_HPRE_TCL hook (input buffers, ICG clone) are ripped as well
if {[info exists ::r37_rip]} { foreach n $::r37_rip { set rip([$n getName]) $n } }
# R37 opt-in QB37_RIP_PORTS 1 (incremental re-route): every port net is ripped too, so DRT re-solves the dense abutted pin
# edges as a whole (r35_act_c ECO 5: kept neighbours -> 'pin not visited' on re-routed act[*] nets, then a crash)
# R37 opt-in QB37_RIP_MACROS 1: every signal net on a macro (BLOCK) pin is ripped too (r35_hubC ECO: kept wires next to
# SRAM pins -> 'pin not visited' on 1-guide hold-buffer nets at EMAB / data pins, then the DRT crash)
if {[qc_env QB37_RIP_MACROS 0]} { foreach i [$blk getInsts] { if {[[$i getMaster] getType] ne "BLOCK"} continue; foreach it [$i getITerms] { set n [$it getNet]; if {$n ne "NULL" && ![$n isSpecial] && [$n getSigType] ne "CLOCK"} { set rip([$n getName]) $n } } } }
if {[qc_env QB37_RIP_PORTS 0]} { foreach b [$blk getBTerms] { set n [$b getNet]; if {$n ne "NULL" && ![$n isSpecial] && [$n getSigType] ne "CLOCK"} { set rip([$n getName]) $n; foreach it [$n getITerms] { set n2 [$it getNet] } } } }
foreach i [$blk getInsts] {
    set nm [$i getName]
    if {![info exists old($nm)] || $old($nm) eq [$i getLocation]} continue
    incr nmov
    foreach it [$i getITerms] { set n [$it getNet]; if {$n ne "NULL" && [$n getSigType] eq "SIGNAL"} { set rip([$n getName]) $n } }
    lappend _movd $i
}
# R37 opt-in QB37_RIP_NEAR <um> (incremental re-route): the signal nets of every cell within <um> of a moved cell are ripped
# too, so no kept wire sits on the moved cell's pins (r35_hubC ECO 4: resized INR2XD4 moved next to kept wires ->
# 'pin not visited' -> DRT-0218 'Guide is not connected to design')
if {[qc_env QB37_RIP_NEAR 0] > 0 && [llength $_movd]} {
    set _r [expr {round([qc_env QB37_RIP_NEAR 0] * [$blk getDefUnits])}]; set _nn 0
    foreach i $_movd {
        set b [$i getBBox]; set x0 [expr {[$b xMin] - $_r}]; set x1 [expr {[$b xMax] + $_r}]; set y0 [expr {[$b yMin] - $_r}]; set y1 [expr {[$b yMax] + $_r}]
        foreach j [$blk getInsts] {
            set c [$j getBBox]; if {[$c xMax] < $x0 || [$c xMin] > $x1 || [$c yMax] < $y0 || [$c yMin] > $y1} continue
            foreach it [$j getITerms] { set n [$it getNet]; if {$n ne "NULL" && ![$n isSpecial] && [$n getSigType] eq "SIGNAL" && ![info exists rip([$n getName])]} { set rip([$n getName]) $n; incr _nn } }
        }
    }
    puts "R35_HOLD R37 rip_near [qc_env QB37_RIP_NEAR 0] um: +$_nn nets around [llength $_movd] moved cells"
}
set nr 0
if {[qc_env QB35_HDR_FULL 1]} {
    # full re-route (default): DRT on top of the kept routing breaks nets whose old wires do not match the new guides
    # (r35_col: 'pin not visited' / checkConnectivity break on act_o feedthroughs), so every signal / clock net is ripped
    foreach n [$blk getNets] { if {[$n isSpecial]} continue; set w [$n getWire]; if {$w ne "NULL"} { odb::dbWire_destroy $w; incr nr } }
} else {
    foreach k [array names rip] { set w [$rip($k) getWire]; if {$w ne "NULL"} { odb::dbWire_destroy $w; incr nr } }
}
puts "R35_HOLD moved_insts $nmov nets_ripped $nr (of [array size rip] touched)"
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
set t [clock seconds]
detailed_route -output_drc $::OUT/rpt/drt_hold.drc.rpt -bottom_routing_layer $::QC_PNR_MIN_LAYER -top_routing_layer $::QC_PNR_MAX_LAYER \
    -droute_end_iter [qc_env QB35_HDR_ITER 64] -verbose 1
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
