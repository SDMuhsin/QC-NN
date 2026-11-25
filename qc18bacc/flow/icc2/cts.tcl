# Clock tree + post-CTS optimisation: clock_opt (CTS with the clock-tree cells of common/lib_cells.tcl qb_clock_cells: the
# site/pnr.tcl clock buffers, CKND<n> inverters and CKLNQD<n> gates, none dont_use; setup / hold / DRV in the MCMM
# scenarios), no useful skew; then the I/O latency (common.tcl qb_io_lat: compute_clock_latency, the median sink latency,
# derated late / early per check as PrimeTime's IO shift).  Block label place -> cts.
# Routing options (qb_route_setup) before clock_opt (R77): clock_opt detail-routes the clock nets, and without the kit
# antenna rules, diodes, port gate size and redundant vias it did so with antenna checking off on the clk port net
# (r75 cts.log [M]: 2 x ZRT-311 on clk) and single vias.
source [file dirname [info script]]/common.tcl
qb_open place cts
set_lib_cell_purpose -exclude cts [get_lib_cells */*]
set ck {}; foreach c [qb_clock_cells] { lappend ck */$c }
set_lib_cell_purpose -include cts [get_lib_cells $ck]
qb_line "cts clock cells [llength $ck]: [join [lmap c $ck { file tail $c }] { }]"
qb_route_setup
set_app_options -name clock_opt.flow.enable_ccd -value false
# Clock gates (R75 [M], results/r75.md): CTS sizes the netlist's CKLNQD1 gates (r74: -> 14 D1, 138 D2, 38 D3, 31 D4, 5 D6,
# 1 D12) to zero slack on its net estimate, and after the detail clock routing below one ends 0.55 fF over its ss limit
# (clk_gate_shd_reg_3, CKLNQD2 Q 0.11905 / 0.1185 pF; the same gate with cts.compile.enable_global_route true, r75).
# ICC2's post-route clock DRC fixing never resizes a clock gate (synthesize_clock_trees -postroute: "Failed subgraph
# evaluation", also with CKLNQD alternatives declared; route_opt's fixer: 0 attempted), though CKLNQD3 fits in place and
# the enable has 3.3 ns slack.  The sign-off ECO fixes it in the clock network (signoff/pt/drv_eco.tcl qb_eco_drc).
# CTS clock design-rule target (R81, PI decision): without one, CTS's only clock DRC limits were the 0.5 ns design max
# transition and the lib pin max_capacitance, and it sized to zero slack against them on its estimate (above), so the
# detail-routed clock nets could end over the sign-off limit and needed the clock ECO.  ICC2 practice (Q-2019.12-SP2
# man set_max_transition / set_max_capacitance, -clock_path: "all pins that are in the network of the specific clocks",
# per scenario; "the most restrictive of the design, clock and pin or port limit is used"; used by clock_opt CTS and the
# route_opt post-route clock DRC fixing): a clock-path max transition in every scenario.  Value = the SDC's own clock
# transition (set_clock_transition, common/constraints.sdc 0.15 ns): the clock slew every pre-CTS timing of this block
# assumed, read from the SDC this run uses, not a new number.  A clock-path max_capacitance is not set: the kit has no
# clock-specific cap limit, the lib pin max_capacitance applies (most restrictive wins) and a driver at <= 0.15 ns output
# slew is far below its lib cap limit, so the transition target is what moves the routed clock nets off the cap limit.
set f [open $::R/$P(TOP)_icc2.sdc]; set t [read $f]; close $f
# (DC writes it per edge: set_clock_transition -max -rise 0.15 ...; the largest -max value)
set ctran [lmap {- v} [regexp -all -inline -line {^set_clock_transition\s+(?:-\S+\s+)*?-max\s+(?:-\S+\s+)*([0-9.]+)\s} $t] { set v }]
if {![llength $ctran]} { error "cts: no set_clock_transition -max in $P(TOP)_icc2.sdc" }
set ctran [tcl::mathfunc::max {*}$ctran]
foreach_in_collection s [all_scenarios] { set_max_transition $ctran -clock_path [get_clocks qb_clk] -scenarios [get_object_name $s] }
qb_line "cts clock_path max_transition $ctran ns (SDC set_clock_transition) in [sizeof_collection [all_scenarios]] scenarios"
qb_io_load
clock_opt
qb_io_lat cts
redirect $::R/rpt/cts_clock_qor.rpt { report_clock_qor -type summary }
foreach l [split [exec cat $::R/rpt/cts_clock_qor.rpt] "\n"] { if {[regexp {qb_clk} $l]} { qb_line "cts [regsub -all {\s+} [string trim $l] { }]" } }
# clock DRC on the detail-routed clock nets, per scenario (tran / cap / fanout / length counts): a clock-gate output
# over its limit here stays to sign-off (above)
redirect $::R/rpt/cts_clock_drc.rpt { report_clock_qor -type drc_violators -nosplit }
set sc {}; foreach l [split [exec cat $::R/rpt/cts_clock_drc.rpt] "\n"] {
    if {[regexp {Scenario: (\S+)} $l -> sc]} continue
    if {[regexp {^qb_clk\s+\S+\s+\d+\s+(\d+)\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\S+\s+(\d+)} $l -> t c f n]} { qb_line "cts clock_drc $sc tran $t cap $c fanout $f length $n" }
}
qb_qor cts
qb_done cts
