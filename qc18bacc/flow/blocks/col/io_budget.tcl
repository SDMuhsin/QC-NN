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
#   act_o  -min  -(Le + Tq) (R78, PI decision): act_o[b] drives the next, identical column's act[b], whose hold checks
#                assume act changes no earlier than Le + Tq (its input -min); act_o's hold contract is that same
#                quantity, from the one proc qb5_hold_min (no capture flop with zero hold at the port exists).  Hold slack
#                act -> act_o = feedthrough min delay - hold uncertainty by construction.  The value is relative to the
#                port's capture clock: PrimeTime's port clock has no latency (capture 0), ICC2's compute_clock_latency
#                I/O latency is late-derated in a hold check (R77 [M] r77 func_ff capture 0.34 vs launch 0.31 ns), so ICC2
#                passes that capture latency Lc and gets Lc - (Le + Tq) (qb5_act_o_min_icc2).  (R78 [M]:
#                -network_latency_included instead removed the capture latency from the act_o -max checks too: cts
#                act -> act_o setup -0.64 ns on all 4608 bits.)
#   act (west, 16 x 288)   max 0.55 P: launch flop + top wire (0.06 P) + 7 upstream feedthroughs (7 x 0.07 P) = column 7
#   act_o (east)           output 0.38 P - U = P - 0.55 P - 0.07 P - U: feedthrough act -> act_o <= 0.07 P per column
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
#   act_o load             qb5_act_o_load: column c's act_o[b] drives column c+1's act[b] (abutment: same bit, same y, an
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
#                          fall x max / min, qb5_act_tran) and set as the act[b] input transition (qb5_act_tran_apply;
#                          ICC2 qb_io_load from CTS on, per scenario; PrimeTime col_blk.tcl until the act_o transitions
#                          it re-measures agree, qb5_act_tran_fix).  No driving cell with it: set_input_transition and
#                          set_driving_cell replace each other per edge (R71 [M] PrimeTime: set_input_transition -rise
#                          -max on act[8] left only the fall / min BUFFD4 entries), and the upstream cell's delay into
#                          this act net is part of the upstream column's act -> act_o path (port to port, timed with this
#                          net as its load), which the 0.55 P act input delay already counts, so the driving cell counted
#                          it twice.  R71 [M] r68 ss: act_o[8] 0.218 / 0.141 ns rise / fall vs 0.034 / 0.024 from the
#                          bare BUFFD4 at act[8].
set ::QB5_FT {BUFFD4 Z}
proc qb5_budget {} {
    set si [expr {[info exists ::env(QB5_SOUTH_IN)] ? $::env(QB5_SOUTH_IN) : 0.20}]
    return [subst -nocommands {
        in  {act[*]}                                   0.55
        in  {cd[*] ctl[*] t2[*]}                       0.30
        in  {pf[*] pw[*] p_ld w_ld s_rd[*] w_r[*] f_vld f_src f_sh w_vld w_sh} $si
        out {act_o[*]}                                 0.38
        out {f_y[*] f_b[*] w_y[*] w_b[*] f_vld_o w_vld_o b2[*] b2_vld} 0.25
    }]
}
# SDC lines of the budget at period per for one corner: clock arrivals Ll (late) / Le (early) at the external registers
# (0 for ideal clocks), Tq = the corner's fastest library clock -> Q (common/lib_cells.tcl qb_lib_tcq, ns, before derate),
# + the act driving cell QB5_FT
# hold contract of the IO min delays (R78): earliest change of an IO signal after the clock edge = early clock arrival Le +
# the fastest library clock -> Q Tq x the early OCV derate; input -min = +, act_o output -min = - this quantity
proc qb5_hold_min {Le Tq} { expr {$Le + $Tq * $::QB_DERATE_EARLY} }
proc qb5_act_o_min_line {Le Tq {Lc 0.0}} {
    format "set_output_delay -min %.4f -clock qb_clk \[get_ports {act_o\[*\]}\]" [expr {$Lc - [qb5_hold_min $Le $Tq]}]
}
proc qb5_io_lines {per Ll Le Tq} {
    set out {}
    set U [expr {[info exists ::env(QC_UNC_SETUP)] ? $::env(QC_UNC_SETUP) : 0.25}]
    set inmin [qb5_hold_min $Le $Tq]
    foreach {d pats mx} [qb5_budget] {
        set su [expr {[string match act_o* $pats] ? $U : 0.0}]
        if {$d eq "in"} {
            lappend out [format "set_input_delay -max %.4f -clock qb_clk \[get_ports {%s}\]" [expr {$mx * $per + $Ll}] $pats]
            lappend out [format "set_input_delay -min %.4f -clock qb_clk \[get_ports {%s}\]" $inmin $pats]
        } else {
            lappend out [format "set_output_delay -max %.4f -clock qb_clk \[get_ports {%s}\]" [expr {$mx * $per - $Le - $su}] $pats]
            lappend out [expr {[string match act_o* $pats] ? [qb5_act_o_min_line $Le $Tq] :
                [format "set_output_delay -min %.4f -clock qb_clk \[get_ports {%s}\]" [expr {-$Ll}] $pats]}]
        }
    }
    lappend out "set_driving_cell -lib_cell [lindex $::QB5_FT 0] -pin [lindex $::QB5_FT 1] \[get_ports {act\[*\]}\]"
    return [join $out "\n"]
}
proc qb5_io_apply {per Ll Le Tq} { foreach l [split [qb5_io_lines $per $Ll $Le $Tq] "\n"] { uplevel #0 $l } }
# ICC2 (flow/icc2/common.tcl qb_io_lat, P(IO_MIN) = {measure apply}, after compute_clock_latency): qb5_act_o_lat_icc2
# measures Le / Lc = the current scenario's launch / capture clock network delay of the min path act[0] -> act_o[0]
# (early / late-derated I/O latency; -scenarios: without it ICC2 reports the worst path over all scenarios, R78 [M]: Le
# 0.340 in every scenario); qb5_act_o_min_icc2 <Le Lc> <Tq> sets act_o -min.  Every scenario is measured before the
# first set (a set_output_delay invalidates the timing: R78 [M] measure / set alternating took ~3 min per scenario)
proc qb5_act_o_lat_icc2 {} {
    redirect -variable r { report_timing -nosplit -delay_type min -scenarios [current_scenario] -from [get_ports {act[0]}] -to [get_ports {act_o[0]}] }
    set v [lmap {- x} [regexp -all -inline -line {^\s*clock network delay \((?:ideal|propagated)\)\s+(-?[0-9.]+)} $r] { set x }]
    if {[llength $v] != 2} { error "qb5_act_o_lat_icc2: [llength $v] clock network delays on act\[0\] -> act_o\[0\] in [get_object_name [current_scenario]]" }
    return $v
}
proc qb5_act_o_min_icc2 {lat Tq} {
    lassign $lat Le Lc
    uplevel #0 [qb5_act_o_min_line $Le $Tq $Lc]
    return [format "Le %.3f Lc %.3f Tq %.4f act_o -min %.4f" $Le $Lc $Tq [expr {$Lc - [qb5_hold_min $Le $Tq]}]]
}
# act_o[b] load = capacitance of the act[b] net.  qb5_act_o_caps <capof>: {b cap ...} of every act[b], capof = command
# prefix called with the act port, returning that net's capacitance in the tool's current timing state; qb5_act_o_load
# <caps>: set_load of each act_o[b].  Separate, because a set_load invalidates the timing (ICC2 also clears the net
# parasitics, TIM-123: R64 [M] reading on after it gave empty / 0 caps), so every corner is measured before the first
# set_load (PrimeTime signoff/pt/col_blk.tcl, ICC2 flow/icc2 qb_io_load).
proc qb5_act_o_caps {capof} {
    set ld {}
    foreach_in_collection p [get_ports {act[*]}] {
        regexp {\[(\d+)\]$} [get_object_name $p] -> b
        set c [{*}$capof $p]
        if {![string is double -strict $c] || $c <= 0} { error "qb5_act_o_caps: no capacitance on [get_object_name $p] ($c)" }
        lappend ld $b $c
    }
    return $ld
}
proc qb5_act_o_load {ld} {
    set v {}
    foreach {b c} $ld { set_load $c [get_ports "act_o\[$b\]"]; lappend v $c }
    set v [lsort -real $v]; set n [llength $v]
    puts [format "QB5_ACT_O_LOAD %d act_o ports, per-bit load = own act net: min %.4f p50 %.4f max %.4f pF" $n \
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
# act[b] input transition = this block's act_o[b] port transition (see the header).  qb5_act_tran: {b {rise_max fall_max
# rise_min fall_min} ...} of every act_o[b] in the tool's current timing state (PrimeTime and ICC2 port attributes
# actual_{rise,fall}_transition_{max,min}); qb5_act_tran_apply <tran>: act[*] driving cell removed, set_input_transition per
# bit and edge (ICC2: the current scenario); qb5_act_tran_fix: measure / apply until a re-measure moves no value by more
# than QB5_TRAN_TOL ns (the act_o transition depends a little on the act slew through the QB5_FT input), error after
# QB5_TRAN_ROUNDS rounds; returns the last residual.
set ::QB5_TRAN_TOL 0.001
set ::QB5_TRAN_ROUNDS 4
proc qb5_act_tran {} {
    set t {}
    foreach_in_collection p [get_ports {act_o[*]}] {
        regexp {\[(\d+)\]$} [get_object_name $p] -> b
        set v {}
        foreach a {actual_rise_transition_max actual_fall_transition_max actual_rise_transition_min actual_fall_transition_min} {
            set x [get_attribute $p $a]
            if {![string is double -strict $x] || $x <= 0} { error "qb5_act_tran: no $a on [get_object_name $p] ($x)" }
            lappend v $x
        }
        lappend t $b $v
    }
    return $t
}
proc qb5_act_tran_apply {t} {
    remove_driving_cell [get_ports {act[*]}]
    set v {}
    foreach {b x} $t {
        set p [get_ports "act\[$b\]"]
        foreach {e m} {rise max fall max rise min fall min} y $x { set_input_transition -$e -$m $y $p }
        lappend v {*}[lrange $x 0 1]
    }
    set v [lsort -real $v]; set n [llength $v]
    puts [format "QB5_ACT_TRAN %d act ports, input transition = own act_o transition (rise / fall max): min %.4f p50 %.4f max %.4f ns" \
        [expr {[llength $t] / 2}] [lindex $v 0] [lindex $v [expr {$n / 2}]] [lindex $v end]]
}
proc qb5_act_tran_diff {t0 t1} {
    set d 0.0
    foreach {b x} $t0 {b1 y} $t1 { foreach u $x w $y { set d [expr {max($d, abs($u - $w))}] } }
    return $d
}
proc qb5_act_tran_fix {} {
    set t [qb5_act_tran]
    for {set i 1} {$i <= $::QB5_TRAN_ROUNDS} {incr i} {
        qb5_act_tran_apply $t
        update_timing
        set t1 [qb5_act_tran]
        set d [qb5_act_tran_diff $t $t1]
        puts [format "QB5_ACT_TRAN_FIX round %d residual %.5f ns" $i $d]
        if {$d <= $::QB5_TRAN_TOL} { return $d }
        set t $t1
    }
    error "qb5_act_tran_fix: act_o transitions still move by [format %.5f $d] ns after $::QB5_TRAN_ROUNDS rounds"
}
