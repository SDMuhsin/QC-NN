# Netlist + P&R SDC of a hard block from its DC run (shared by the block configs blocks/col/col.cfg, blocks/act/act.cfg):
#   P(NETLIST) = <syn>/<top>.v; when QC_PNR_OUT is set and <syn>/<top>.sdc exists, the DC SDC without the -min (ff / lt)
#   operating condition (OpenROAD here loads the tt liberty only, STA-0115 otherwise) and without the per-net set_load /
#   set_resistance of a topographical run is written to $QC_PNR_OUT/<top>_pnr.sdc = P(SDC).  QB_PNR_PERIOD
#   (results/pnr_slice2.md): DC synthesised with a setup margin (shorter period); P&R re-times the netlist at this
#   period: clock period, IO delays (20 % of it) and max transition (min(0.5, 0.1 P)).
# Sourced at config level after P(TOP) / P(SYN) are set (globals _s _f _t _p _p0 as before).
set _s [expr {[file isdirectory $P(SYN)] ? $P(SYN) : "$::QC_BUILD/syn/$P(SYN)"}]
set P(NETLIST) $_s/$P(TOP).v
if {[info exists ::env(QC_PNR_OUT)] && [file exists $_s/$P(TOP).sdc]} {
    set _f [open $_s/$P(TOP).sdc]; set _t [read $_f]; close $_f
    regsub -all {\\\n\s*-min \S+ -min_library \S+} $_t {} _t
    # DC topographical writes its estimated per-net load / resistance (1.2 M lines): drop them, P&R has real RC
    regsub -all -line {^set_(load|resistance) .*\[get_nets .*$} $_t {} _t
    # QB_PNR_PERIOD (results/pnr_slice2.md): DC synthesised with a setup margin (shorter period); P&R re-times the
    # netlist at this period: clock period, IO delays (20 % of it) and max transition (min(0.5, 0.1 P))
    if {[info exists ::env(QB_PNR_PERIOD)]} {
        set _p $::env(QB_PNR_PERIOD)
        regexp -line {^create_clock .*-period ([0-9.]+)} $_t -> _p0
        regsub -all -line {(^create_clock .*-period )[0-9.]+(\s+-waveform )\{[^\}]*\}} $_t \
            "\\1$_p\\2{0 [expr {0.5 * $_p}]}" _t
        regsub -all -line {(^set_(input|output)_delay -clock qb_clk\s+)[0-9.]+} $_t "\\1[expr {0.2 * $_p}]" _t
        regsub -all -line {(^set_max_transition )[0-9.]+} $_t "\\1[expr {min(0.5, 0.1 * $_p)}]" _t
        puts "QB_PNR_PERIOD: DC period $_p0 -> $_p ns (IO delay, max transition rescaled)"
    }
    set _f [open $::env(QC_PNR_OUT)/$P(TOP)_pnr.sdc w]; puts -nonewline $_f $_t; close $_f
    set P(SDC) $::env(QC_PNR_OUT)/$P(TOP)_pnr.sdc
}
