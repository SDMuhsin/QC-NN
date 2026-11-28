# IO budget of the column hard block qb_col_blk (results/r5a.md) for the R5b top, as fractions of the period P.
# Delays are relative to the clock at the top-level flops; the top-level tree is balanced with the block's internal
# sinks, so after CTS they are shifted by the clock arrival at those flops: PrimeTime the p50 late arrival Ll (late OCV
# derate on the clock path) and the p50 early arrival Le (early derate) of the block's own register clock pins, measured
# per corner (signoff/pt/io_lat.tcl qb_clk_arrival; R77); ICC2 the same ends through compute_clock_latency (median sink
# latency as the I/O clock latency, derated late / early per check: flow/icc2/common.tcl qb_io_lat), so it applies the
# unshifted budget (Ll = Le = 0 here).  Each check takes the external register's clock arrival that is pessimistic for
# it, as OCV does for an internal path (late launch / early capture for setup, early launch / late capture for hold):
#   input  -max  budget + Ll     (upstream register launches late)       input  -min  Le + Tq (below)
#   output -max  budget - Le     (downstream register captures early)    output -min  0 - Ll (captures late)
#   act    -min  Le + H (R81, PI decision; R108): H = QC_ACT_HOLD_HUB, the act hold budget allocated once, to the act source;
#                the chain's one hold guarantee common/act_chain.tcl qb_act_earliest (act changes no earlier than H after
#                the clock edge, the launching flop's clock -> Q included, so no Tq on top: R108 [S], it was counted twice
#                before).  act is a point-to-point chain of identical columns, each adding its feedthrough, so the
#                earliest act arrival at any column is the source's guaranteed minimum (pf / pw / the other inputs keep
#                Le + Tq)
#   act_o  -min  -(Le + H - U_hold) (R78/R79/R81, PI decisions; R108): act_o[b] drives the next, identical column's act[b],
#                whose hold checks assume act changes no earlier than Le + H (its input -min); act_o's hold contract is
#                that same guarantee at a driving port, common/act_chain.tcl qb_act_out_min (as the act source's act
#                output; no capture flop with zero hold at the port exists): minus the hold uncertainty U_hold (R79, PI
#                decision: charged once, at the next column's act capture flop; see qb5_act_o_min).  Hold slack act ->
#                act_o = feedthrough min delay by construction.  The value is relative to the
#                port's capture clock: PrimeTime's port clock has no latency (capture 0), ICC2's compute_clock_latency
#                I/O latency is late-derated in a hold check (R77 [M] r77 func_ff capture 0.34 vs launch 0.31 ns), so ICC2
#                passes that capture latency Lc and gets Lc - (Le + H - U_hold) (qb5_act_o_min_icc2).  (R78 [M]:
#                -network_latency_included instead removed the capture latency from the act_o -max checks too: cts
#                act -> act_o setup -0.64 ns on all 4608 bits.)
#   act (west, 16 x 288)   max 0.55 P: the act source's launch + wire QB_ACT_LAUNCH (0.06 P; common/act_chain.tcl
#                          qb_act_launch, = the act source's own output budget) + 7 upstream feedthroughs (7 x QB5_ACT_FT
#                          0.07 P) = column 7
#   act_o (east)           output 0.38 P - U = P - 0.55 P - 0.07 P - U: feedthrough act -> act_o <= QB5_ACT_FT 0.07 P per column
#                          (U = setup uncertainty QC_UNC_SETUP 0.25 ns, counted once on the top-level flop -> flop path)
#   north inputs           cd / ctl / t2 (codes, item controls, T2): 0.30 P
#   south inputs           pf / pw / p_ld / w_ld (parameter loads), s_rd / w_r (stream reads), f_vld / f_src / f_sh /
#                          w_vld / w_sh (PPU controls): QB5_SOUTH_IN (default 0.20 P, as the column / slice runs)
#   south outputs          f_y / f_b / w_y / w_b / *_vld_o (lane results), b2 / b2_vld: 0.25 P
#   min (hold) input delay Tq on every input (R77; was 0.05 P, which grew with the period: 0.325 ns at the 6.5 ns sign-off
#                          vs 0.25 in P&R): the earliest an input can change after its launching clock edge is the
#                          fastest clock -> Q of any library flip-flop at that corner (common/lib_tcq.py: smallest
#                          cell_rise / cell_fall entry of every non-dont_use flop's clock -> Q arc, i.e. at the lowest
#                          characterised slew and load), x the early OCV derate, with zero wire / logic after it: a lower
#                          bound for every input whatever drives it (column 0 act from a near flop, the north / south
#                          inputs from hub registers, act of column c > 0 through c feedthroughs that only add delay),
#                          independent of the period, the same in ICC2 and PrimeTime (common/lib_cells.tcl qb_lib_tcq;
#                          after CTS + Le, in ICC2 through compute_clock_latency);
#                          output min 0
#   act_o load             qb5_io_load act_o: column c's act_o[b] drives column c+1's act[b] (abutment: same bit, same y, an
#                          identical block), so act_o[b] gets the capacitance of this block's own act[b] net, per bit
#                          (pins + wire of the current timing state).  Per bit, not the max over the bits: the load of
#                          bit b is exactly that of the same net in the next column (R63 [M] ss ETM act pins p50 0.037,
#                          max 0.088 pF), so the max would over-load most of the 4608 feedthroughs ~2x.  It replaces the
#                          common 4 x INVD4 (constraints.sdc, 0.0187 pF), which is not what an abutted act_o drives.
#   act driving cell       column c's act[b] is driven by column c-1's act_o[b] feedthrough buffer.  R68 (PI decision):
#                          the 4608 feedthroughs are one fixed lib cell QB5_FT, sized and dont_touch in ICC2 init
#                          (flow/icc2/init.tcl P(FEEDTHRU_CELL)) and dont_touch in PrimeTime (qb5_ft_cells), so act[*]
#                          gets exactly that cell as its driving cell (a line of qb5_io_lines, every corner, P&R and
#                          sign-off alike) and ICC2 closes act -> act_o itself (R67: ICC2 resized the per-bit drivers
#                          after reading them, PT needed 4 setup ECO rounds).  Size: the smallest BUFFD* that meets the
#                          0.07 P feedthrough budget at the worst setup corner with the per-bit act_o load (results/r68.md).
#                          That driving cell is the pre-layout estimate only (ICC2 init / place).
#   act input transition   R71 (PI decision): act[b] of column c is the abutted act_o[b] of column c-1, an identical block,
#                          so its transition is this block's own act_o[b] port transition of the same corner: the QB5_FT
#                          cell through the act_o wire into the act_o load above, measured by the timer per bit (rise /
#                          fall x max / min, qb5_io_tran) and set as the act[b] input transition (qb5_io_tran_apply;
#                          ICC2 qb_io_load from CTS on, per scenario; PrimeTime col_blk.tcl until the act_o transitions
#                          it re-measures agree, qb5_io_tran_fix).  No driving cell with it: set_input_transition and
#                          set_driving_cell replace each other per edge (R71 [M] PrimeTime: set_input_transition -rise
#                          -max on act[8] left only the fall / min BUFFD4 entries), and the upstream cell's delay into
#                          this act net is part of the upstream column's act -> act_o path (port to port, timed with this
#                          net as its load), which the 0.55 P act input delay already counts, so the driving cell counted
#                          it twice.  R71 [M] r68 ss: act_o[8] 0.218 / 0.141 ns rise / fall vs 0.034 / 0.024 from the
#                          bare BUFFD4 at act[8].
# (QC_UNC_SETUP / QC_UNC_HOLD / QB5_SOUTH_IN: common/limits.txt through qb_limit, R99; the act chain's QC_ACT_HOLD_HUB /
# QB_ACT_LAUNCH through common/act_chain.tcl, R107)
source [file join [file dirname [file normalize [info script]]] .. .. common act_chain.tcl]
set ::QB5_FT {BUFFD4 Z}
# act feedthrough budget per column (fraction of P) and the columns upstream of the last one
set ::QB5_ACT_FT 0.07
set ::QB5_ACT_UPSTREAM 7
# the act input -max shift of a column at period per (common/act_chain.tcl qb_act_in_max): the late clock arrival Ll at the
# external registers + the upstream feedthroughs (qb_act_chain_check below, signoff/pt/col_blk.tcl feedthrough_delay)
proc qb5_act_smax {per Ll} { expr {$Ll + $::QB5_ACT_UPSTREAM * $::QB5_ACT_FT * $per} }
proc qb5_budget {} {
    # opt-in: a block that reuses these procs sets its own class table ::QB5_BUDGET before sourcing (blocks/rgr/io_budget.tcl)
    if {[info exists ::QB5_BUDGET]} { return $::QB5_BUDGET }
    set si [qb_limit QB5_SOUTH_IN]
    set ai [expr {[qb_act_launch] + $::QB5_ACT_UPSTREAM * $::QB5_ACT_FT}]
    set ao [expr {1.0 - $ai - $::QB5_ACT_FT}]
    return [subst -nocommands {
        in  {act[*]}                                   $ai
        in  {cd[*] ctl[*] t2[*]}                       0.30
        in  {pf[*] pw[*] p_ld w_ld s_rd[*] w_r[*] f_vld f_src f_sh w_vld w_sh} $si
        out {act_o[*]}                                 $ao
        out {f_y[*] f_b[*] w_y[*] w_b[*] f_vld_o w_vld_o b2[*] b2_vld} 0.25
    }]
}
# SDC lines of the budget at period per for one corner: clock arrivals Ll (late) / Le (early) at the external registers
# (0 for ideal clocks), Tq = the corner's fastest library clock -> Q (common/lib_cells.tcl qb_lib_tcq, ns, before derate),
# + the act driving cell QB5_FT
# hold contract of the IO min delays (R78): earliest change of an IO signal after the clock edge = early clock arrival Le +
# the fastest library clock -> Q Tq x the early OCV derate = every input's -min but act (act / act_o: the act chain's
# guarantee, common/act_chain.tcl, R108)
proc qb5_hold_min {Le Tq} { expr {$Le + $Tq * $::QB_DERATE_EARLY} }
# hold uncertainty U_hold of the SDC: the variable common/constraints.sdc reads (QC_UNC_HOLD, PrimeTime) and DC wrote
# into the SDC ICC2 reads (flow/icc2/init.tcl qb_sdc checks the two agree)
proc qb5_unc_hold {} { qb_limit QC_UNC_HOLD }
# act_o -min (R79, PI decision): hold uncertainty is charged ONCE, at the real capture register.  act -> act_o is a
# port-to-port budget path with no capture flop in this block; the next column charges U_hold at its own act capture
# flop.  The timer adds U_hold to every hold check at the act_o port, so the contract hands it back: act_o -min =
# U_hold - (Le + H) (common/act_chain.tcl qb_act_out_min, + Lc in ICC2, header), i.e. hold slack act -> act_o = the
# feedthrough min delay, without a second U_hold.  No new constant, no margin; one place for ICC2 and PrimeTime.
# act input -min (R81, PI decision; R108, header): the chain's one guarantee qb_act_earliest Le = Le + H.  The budget is a
# property of the act SOURCE, not of each column: every column sees the source's minimum arrival plus its upstream
# feedthroughs, which only add delay.
proc qb5_act_o_min {Le {Lc 0.0}} { expr {$Lc + [qb_act_out_min $Le]} }
proc qb5_act_o_min_line {Le {Lc 0.0}} {
    format "set_output_delay -min %.4f -clock qb_clk \[get_ports {act_o\[*\]}\]" [qb5_act_o_min $Le $Lc]
}
proc qb5_io_lines {per Ll Le Tq} {
    set out {}
    set U [qb_limit QC_UNC_SETUP]
    set inmin [qb5_hold_min $Le $Tq]
    foreach {d pats mx} [qb5_budget] {
        set su [expr {[string match act_o* $pats] ? $U : 0.0}]
        if {$d eq "in"} {
            lappend out [format "set_input_delay -max %.4f -clock qb_clk \[get_ports {%s}\]" [expr {$mx * $per + $Ll}] $pats]
            # (R81 / R108: act gets the chain's hold guarantee, qb_act_earliest; every other input the generic bound)
            set mn [expr {$pats eq {act[*]} ? [qb_act_earliest $Le] : $inmin}]
            lappend out [format "set_input_delay -min %.4f -clock qb_clk \[get_ports {%s}\]" $mn $pats]
        } else {
            lappend out [format "set_output_delay -max %.4f -clock qb_clk \[get_ports {%s}\]" [expr {$mx * $per - $Le - $su}] $pats]
            lappend out [expr {[string match act_o* $pats] ? [qb5_act_o_min_line $Le] :
                [format "set_output_delay -min %.4f -clock qb_clk \[get_ports {%s}\]" [expr {-$Ll}] $pats]}]
        }
    }
    # (the act driving cell only where the budget has the act class: every column; not a ::QB5_BUDGET block without act)
    # (and the act chain contract check, R107: act -max = the source's launch + the upstream feedthroughs, -min = the
    # chain's hold guarantee at this block's clock edge Le, R108)
    if {[lsearch -exact [qb5_budget] {act[*]}] >= 0} {
        lappend out "set_driving_cell -lib_cell [lindex $::QB5_FT 0] -pin [lindex $::QB5_FT 1] \[get_ports {act\[*\]}\]"
        qb_act_chain_check col [join $out "\n"] $per [qb5_act_smax $per $Ll] $Le
    }
    return [join $out "\n"]
}
proc qb5_io_apply {per Ll Le Tq} { foreach l [split [qb5_io_lines $per $Ll $Le $Tq] "\n"] { uplevel #0 $l } }
# ICC2 (flow/icc2/common.tcl qb_io_lat, P(IO_MIN) = {measure apply}, after compute_clock_latency): qb5_act_o_lat_icc2
# measures Le / Lc = the current scenario's launch / capture clock network delay of the min path act[0] -> act_o[0]
# (early / late-derated I/O latency; -scenarios: without it ICC2 reports the worst path over all scenarios, R78 [M]: Le
# 0.340 in every scenario); qb5_act_o_min_icc2 <Le Lc> sets act_o -min.  Every scenario is measured before the
# first set (a set_output_delay invalidates the timing: R78 [M] measure / set alternating took ~3 min per scenario).
# -significant_digits 6 (R92): at the report's default 2 the 0.1-ps act_o -min line was built from latencies rounded to
# 10 ps (r91b [M]: ICC2's act_o hold contract -9.0 .. +4.8 ps off PrimeTime's on 4,608 ports)
proc qb5_act_o_lat_icc2 {} {
    redirect -variable r { report_timing -nosplit -significant_digits 6 -delay_type min -scenarios [current_scenario] -from [get_ports {act[0]}] -to [get_ports {act_o[0]}] }
    set v [lmap {- x} [regexp -all -inline -line {^\s*clock network delay \((?:ideal|propagated)\)\s+(-?[0-9.]+)} $r] { set x }]
    if {[llength $v] != 2} { error "qb5_act_o_lat_icc2: [llength $v] clock network delays on act\[0\] -> act_o\[0\] in [get_object_name [current_scenario]]" }
    return $v
}
proc qb5_act_o_min_icc2 {lat} {
    lassign $lat Le Lc
    uplevel #0 [qb5_act_o_min_line $Le $Lc]
    return [format "Le %.4f Lc %.4f H %.3f U_hold %.3f act_o -min %.4f" $Le $Lc [qb_act_hold] [qb5_unc_hold] [qb5_act_o_min $Le $Lc]]
}
# Per-bit IO of an abutted chain of identical blocks (out[b] of one drives in[b] of the next; the column: act_o -> act,
# the regression block: y_o -> x, blocks/rgr/io_budget.tcl; R109: generic, was act / act_o only).  Load: out[b] =
# capacitance of the own in[b] net.  qb5_io_caps <in> <capof>: {b cap ...} of every <in>[b], capof = command prefix
# called with the port, returning that net's capacitance in the tool's current timing state; qb5_io_load <out> <caps>:
# set_load of each <out>[b].  Separate, because a set_load invalidates the timing (ICC2 also clears the net parasitics,
# TIM-123: R64 [M] reading on after it gave empty / 0 caps), so every corner is measured before the first set_load
# (PrimeTime signoff/pt/col_blk.tcl, ICC2 flow/icc2 qb_io_load).  ICC2 applies set_load to the current corner and
# set_input_transition to the current scenario (man; R109 [M] tau14 rgr route label, set in func_ss / ff / tt, read back
# 0.011 / 0.022 / 0.033 pF and 0.101 / 0.202 / 0.303 ns there, func_wcl unchanged): per scenario here, one per corner.
proc qb5_io_caps {in capof} {
    set ld {}
    foreach_in_collection p [get_ports "$in\[*\]"] {
        regexp {\[(\d+)\]$} [get_object_name $p] -> b
        set c [{*}$capof $p]
        if {![string is double -strict $c] || $c <= 0} { error "qb5_io_caps: no capacitance on [get_object_name $p] ($c)" }
        lappend ld $b $c
    }
    if {![llength $ld]} { error "qb5_io_caps: no port $in\[*\]" }
    return $ld
}
proc qb5_io_load {out ld} {
    set v {}
    foreach {b c} $ld { set_load $c [get_ports "$out\[$b\]"]; lappend v $c }
    set v [lsort -real $v]; set n [llength $v]
    puts [format "QB5_IO_LOAD %d %s ports, per-bit load = own input net: min %.4f p50 %.4f max %.4f pF" $n $out \
        [lindex $v 0] [lindex $v [expr {$n / 2}]] [lindex $v end]]
}
# the feedthrough buffers (ICC2 init sized them to QB5_FT, flow/icc2/init.tcl): the one leaf driver of every act_o[b]
# net, each a QB5_FT cell (error otherwise); PrimeTime (signoff/pt/col_blk.tcl) checks and dont_touches them
proc qb5_ft_cells {} {
    set d [get_pins -quiet -leaf -of_objects [get_nets -of_objects [get_ports {act_o[*]}]] -filter "direction==out"]
    set c [get_cells -of_objects $d]
    set n [sizeof_collection [get_ports {act_o[*]}]]
    if {[sizeof_collection $d] != $n || [sizeof_collection $c] != $n} { error "qb5_ft_cells: [sizeof_collection $d] drivers / [sizeof_collection $c] cells for $n act_o ports" }
    set bad [filter_collection $c "ref_name != [lindex $::QB5_FT 0]"]
    if {[sizeof_collection $bad]} { error "qb5_ft_cells: [sizeof_collection $bad] feedthroughs not [lindex $::QB5_FT 0], e.g. [get_object_name [index_collection $bad 0]] [get_attribute [index_collection $bad 0] ref_name]" }
    return $c
}
# Input transition of the chain: in[b] = this block's own out[b] port transition (the column: see the header).
# qb5_io_tran <out>: {b {rise_max fall_max rise_min fall_min} ...} of every <out>[b] in the tool's current timing state
# (PrimeTime and ICC2 port attributes actual_{rise,fall}_transition_{max,min}); qb5_io_tran_apply <in> <tran>: <in>[*]
# driving cell removed, set_input_transition per bit and edge (ICC2: the current scenario); qb5_io_tran_diff <t0> <t1>:
# the largest change; qb5_io_tran_fix <in> <out> (PrimeTime, signoff/pt/col_blk.tcl, rgr_blk.tcl): measure / apply until a re-measure moves no value by more
# than QB5_TRAN_TOL ns (the act_o transition depends a little on the act slew through the QB5_FT input), error after
# QB5_TRAN_ROUNDS rounds; returns the last residual.
set ::QB5_TRAN_TOL 0.001
set ::QB5_TRAN_ROUNDS 4
proc qb5_io_tran {out} {
    set t {}
    foreach_in_collection p [get_ports "$out\[*\]"] {
        regexp {\[(\d+)\]$} [get_object_name $p] -> b
        set v {}
        foreach a {actual_rise_transition_max actual_fall_transition_max actual_rise_transition_min actual_fall_transition_min} {
            set x [get_attribute $p $a]
            if {![string is double -strict $x] || $x <= 0} { error "qb5_io_tran: no $a on [get_object_name $p] ($x)" }
            lappend v $x
        }
        lappend t $b $v
    }
    if {![llength $t]} { error "qb5_io_tran: no port $out\[*\]" }
    return $t
}
proc qb5_io_tran_apply {in t} {
    remove_driving_cell [get_ports "$in\[*\]"]
    set v {}
    foreach {b x} $t {
        set p [get_ports "$in\[$b\]"]
        foreach {e m} {rise max fall max rise min fall min} y $x { set_input_transition -$e -$m $y $p }
        lappend v {*}[lrange $x 0 1]
    }
    set v [lsort -real $v]; set n [llength $v]
    puts [format "QB5_IO_TRAN %d %s ports, input transition = own output transition (rise / fall max): min %.4f p50 %.4f max %.4f ns" \
        [expr {[llength $t] / 2}] $in [lindex $v 0] [lindex $v [expr {$n / 2}]] [lindex $v end]]
}
proc qb5_io_tran_diff {t0 t1} {
    set d 0.0
    foreach {b x} $t0 {b1 y} $t1 { foreach u $x w $y { set d [expr {max($d, abs($u - $w))}] } }
    return $d
}
proc qb5_io_tran_fix {in out} {
    set t [qb5_io_tran $out]
    for {set i 1} {$i <= $::QB5_TRAN_ROUNDS} {incr i} {
        qb5_io_tran_apply $in $t
        update_timing
        set t1 [qb5_io_tran $out]
        set d [qb5_io_tran_diff $t $t1]
        puts [format "QB5_IO_TRAN_FIX $in round %d residual %.5f ns" $i $d]
        if {$d <= $::QB5_TRAN_TOL} { return $d }
        set t $t1
    }
    error "qb5_io_tran_fix: $out transitions still move by [format %.5f $d] ns after $::QB5_TRAN_ROUNDS rounds"
}
# act noise state (R92, PI decision; PrimeTime only): a second, explicit analysis state for the SI noise analysis.  The
# timing state above (R71: measured input transitions, no driving cell) leaves PrimeTime without a holding driver on the
# 4608 act nets (R92 [M]: "Steady state resistance source: estimation failure default", bumps 2 - 7x too small), and a
# driving cell in the timing state would add its load-dependent delay at the port, which the upstream column's act ->
# act_o path already contains (R71; R92 [M] 16 - 99 ps).  In the noise state act[b] is driven by the previous column's
# feedthrough buffer QB5_FT (PrimeTime then holds the net with the cell's CCS-noise I-V curve), driven with this block's
# own QB5_FT input slew of the bit, and its port load is the previous column's act_o wire = this block's extracted
# act_o[b] wire capacitance of the corner.
#   qb5_act_noise_driver        timing state -> noise state; saves the timing state of every act port (its four input
#                               transitions; error if the port is not in that state or already has a port load).  Call
#                               it after the last timing result: nothing timed in the noise state is sign-off timing.
#   qb5_act_noise_driver off    back to the saved timing state (the ECO: noise pass, then timing passes again)
# Returns a one-line record of what it did.
proc qb5_act_noise_driver {{mode on}} {
    set A [get_ports {act[*]}]
    set ks {input_transition_rise_max input_transition_fall_max input_transition_rise_min input_transition_fall_min}
    if {$mode eq "off"} {
        if {![info exists ::QB5_ACT_TIMING_STATE]} { error "qb5_act_noise_driver off: not in the noise state" }
        remove_driving_cell $A
        remove_capacitance $A
        foreach {b t} $::QB5_ACT_TIMING_STATE {
            foreach {e m} {rise max fall max rise min fall min} y $t { set_input_transition -$e -$m $y [get_ports "act\[$b\]"] }
        }
        unset ::QB5_ACT_TIMING_STATE
        return "act timing state restored on [sizeof_collection $A] ports (input transitions, no driving cell, no port load)"
    }
    if {[info exists ::QB5_ACT_TIMING_STATE]} { error "qb5_act_noise_driver: already in the noise state" }
    set st {}; set plan {}; set cws {}
    foreach_in_collection p $A {
        regexp {\[(\d+)\]$} [get_object_name $p] -> b
        set t {}
        foreach k $ks {
            set x [get_attribute -quiet $p $k]
            if {![string is double -strict $x] || $x <= 0} { error "qb5_act_noise_driver: no $k on act\[$b\] (not in the timing state)" }
            lappend t $x
        }
        foreach k {pin_capacitance_max wire_capacitance_max} {
            set x [get_attribute -quiet $p $k]
            if {[string is double -strict $x] && $x != 0} { error "qb5_act_noise_driver: act\[$b\] already has a port load ($k $x)" }
        }
        set on [get_nets -of_objects [get_ports "act_o\[$b\]"]]
        set fi [get_pins -of_objects [get_cells -of_objects [get_pins -leaf -of_objects $on -filter "direction==out"]] -filter "direction==in"]
        set cw [get_attribute $on wire_capacitance_max]
        if {[sizeof_collection $fi] != 1 || ![string is double -strict $cw] || $cw <= 0} { error "qb5_act_noise_driver: act_o\[$b\]: [sizeof_collection $fi] feedthrough input pins, wire capacitance '$cw'" }
        lappend st $b $t; lappend cws $cw
        lappend plan $p [get_attribute $fi actual_rise_transition_max] [get_attribute $fi actual_fall_transition_max] $cw
    }
    foreach {p r f cw} $plan {
        set_driving_cell -lib_cell [lindex $::QB5_FT 0] -pin [lindex $::QB5_FT 1] -input_transition_rise $r -input_transition_fall $f -no_design_rule $p
        set_load $cw $p
    }
    set ::QB5_ACT_TIMING_STATE $st
    set cws [lsort -real $cws]; set n [llength $cws]
    return [format "%d act ports driven by %s/%s with the own feedthrough input slew, port load = own act_o wire capacitance min %.4f p50 %.4f max %.4f pF" \
        $n [lindex $::QB5_FT 0] [lindex $::QB5_FT 1] [lindex $cws 0] [lindex $cws [expr {$n / 2}]] [lindex $cws end]]
}
