# P&R SDC from a DC run (as impl/pnr/slice.cfg): DC SDC without the -min operating condition and the topographical
# per-net set_load / set_resistance lines; QB_PNR_PERIOD re-times it (clock, IO delays 20 %, max transition).
proc qb_sdc_pnr {syn top} {
    upvar 1 P P
    if {![info exists ::env(QC_PNR_OUT)] || ![file exists $syn/$top.sdc]} { return }
    set _f [open $syn/$top.sdc]; set _t [read $_f]; close $_f
    regsub -all {\\\n\s*-min \S+ -min_library \S+} $_t {} _t
    regsub -all -line {^set_(load|resistance) .*\[get_nets .*$} $_t {} _t
    if {[info exists ::env(QB_PNR_PERIOD)]} {
        set _p $::env(QB_PNR_PERIOD)
        regexp -line {^create_clock .*-period ([0-9.]+)} $_t -> _p0
        regsub -all -line {(^create_clock .*-period )[0-9.]+(\s+-waveform )\{[^\}]*\}} $_t \
            "\\1$_p\\2{0 [expr {0.5 * $_p}]}" _t
        regsub -all -line {(^set_(input|output)_delay -clock qb_clk\s+)[0-9.]+} $_t "\\1[expr {0.2 * $_p}]" _t
        regsub -all -line {(^set_max_transition )[0-9.]+} $_t "\\1[expr {min(0.5, 0.1 * $_p)}]" _t
        puts "QB_PNR_PERIOD: DC period $_p0 -> $_p ns (IO delay, max transition rescaled)"
    }
    set _f [open $::env(QC_PNR_OUT)/${top}_pnr.sdc w]; puts -nonewline $_f $_t; close $_f
    set P(SDC) $::env(QC_PNR_OUT)/${top}_pnr.sdc
}
