# Netlist + P&R SDC of a hard block from its DC run (flow/icc2/init.tcl, every block config):
#   P(NETLIST) = <syn>/<top>.v; when QC_PNR_OUT is set and <syn>/<top>.sdc exists, the DC SDC without the -min (ff / lt)
#   operating condition (OpenROAD here loads the tt liberty only, STA-0115 otherwise) and without the per-net set_load /
#   set_resistance of a topographical run is written to $QC_PNR_OUT/<top>_pnr.sdc = P(SDC).  QB_PNR_PERIOD
#   (results/pnr_slice2.md): DC synthesised with a setup margin (shorter period); P&R re-times the netlist at this
#   period: clock period, IO delays and max transition from the sign-off limits at that period (common/limits.tcl
#   qb_io_delay / qb_max_tran, R103; were hard-coded 0.2 P and min(0.5, 0.1 P), a second source beside limits.txt).
# Sourced at config level after P(TOP) / P(SYN) are set (globals _s _f _t _p _p0 as before).
set _s [expr {[file isdirectory $P(SYN)] ? $P(SYN) : "$::QC_BUILD/syn/$P(SYN)"}]
set P(NETLIST) $_s/$P(TOP).v
if {[info exists ::env(QC_PNR_OUT)] && [file exists $_s/$P(TOP).sdc]} {
    set _f [open $_s/$P(TOP).sdc]; set _t [read $_f]; close $_f
    regsub -all {\\\n\s*-min \S+ -min_library \S+} $_t {} _t
    # DC topographical writes its estimated per-net load / resistance (1.2 M lines): delete them (with their newline: R59
    # left 1.43 M blank lines in the ICC2 SDC), P&R has real RC
    regsub -all -line {^set_(load|resistance) .*\[get_nets .*\n} $_t {} _t
    # QB_PNR_PERIOD (results/pnr_slice2.md): DC synthesised with a setup margin (shorter period); P&R re-times the
    # netlist at this period: clock period, IO delays (qb_io_delay) and max transition (qb_max_tran)
    # Each rewrite is counted (R107; hunt round 11 on d1978e1: none was checked, and the period pattern needs -waveform):
    # an error unless every create_clock line (at least one) and exactly one design set_max_transition were rewritten;
    # the IO delay lines rewritten / present are logged (a block IO budget replaces them: icc2/init.tcl qb_sdc, which
    # also reads the clock period back against QB_PNR_PERIOD)
    if {[info exists ::env(QB_PNR_PERIOD)]} {
        set _p $::env(QB_PNR_PERIOD)
        set _p0 none; regexp -line {^create_clock .*-period ([0-9.]+)} $_t -> _p0
        set _n [regexp -all -line {^create_clock } $_t]
        set _nc [regsub -all -line {(^create_clock .*-period )[0-9.]+(\s+-waveform )\{[^\}]*\}} $_t \
            "\\1$_p\\2{0 [expr {0.5 * $_p}]}" _t]
        if {$_n < 1 || $_nc != $_n} { error "common/block_sdc.tcl: QB_PNR_PERIOD $_p rewrote $_nc of $_n create_clock lines of $_s/$P(TOP).sdc (want all, at least one: create_clock ... -period <p> -waveform {...})" }
        set _ni [regexp -all -line {^set_(input|output)_delay } $_t]
        set _nio [regsub -all -line {(^set_(input|output)_delay -clock qb_clk\s+)[0-9.]+} $_t "\\1[qb_io_delay $_p]" _t]
        set _nt [regsub -all -line {(^set_max_transition )[0-9.]+( \[current_design\])} $_t "\\1[qb_max_tran $_p]\\2" _t]
        if {$_nt != 1} { error "common/block_sdc.tcl: QB_PNR_PERIOD $_p rewrote $_nt design set_max_transition lines of $_s/$P(TOP).sdc (want 1)" }
        puts "QB_PNR_PERIOD: DC period $_p0 -> $_p ns: create_clock $_nc, max transition $_nt, IO delay $_nio of $_ni lines rescaled"
    }
    set _f [open $::env(QC_PNR_OUT)/$P(TOP)_pnr.sdc w]; puts -nonewline $_f $_t; close $_f
    set P(SDC) $::env(QC_PNR_OUT)/$P(TOP)_pnr.sdc
}
