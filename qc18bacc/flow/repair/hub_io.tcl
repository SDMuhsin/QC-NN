# Hub QB35_IO_TCL of repair/hold_eco.tcl (results/r37.md sec. 9): clock at the chip period QB35_PER, the run's hub
# IO budget (blocks/hub/sdc.py hub_io.tcl, QB37_HUBIO) at the PT-measured tt p50 insertion delay QB35_IOL, in2out feed-through
# paths false for setup (timed at chip level, as the pt37 sign-off).  (The R37 per-port tightening QB37_SSX that stood in for
# ss in a tt-only repair was removed in R50: the repair session times ss itself, repair/hold_eco.tcl.)
set _p $::env(QB35_PER)
create_clock -name qb_clk -period $_p -waveform [list 0 [expr {$_p / 2.0}]] [get_ports clk]
set_clock_uncertainty -setup 0.25 [get_clocks qb_clk]; set_clock_uncertainty -hold 0.05 [get_clocks qb_clk]
set_propagated_clock [all_clocks]
source $::env(QB37_HUBIO)
qb9_io_apply $_p $::env(QB35_IOL)
set_false_path -setup -from [all_inputs] -to [all_outputs]
# budget fractions of blocks/hub/sdc.py (B)
array set _fr {colin 0.27 colout 0.20 colnorth 0.55 actout 0.30 actin 0.40 topin 0.40 topout 0.40 hostin 0.30}
array set _cls {}
foreach k [array names ::QB9_IO] { foreach p $::QB9_IO($k) { set _cls($p) $k } }
# QB37_FR "<class> <fraction> ...": budget re-split of whole classes (actout 0.26 with the act QB7_DIN 0.74: the output delay is the external share)
foreach {k v} [qc_env QB37_FR ""] { set _fr($k) $v }
foreach {k v} [qc_env QB37_FR ""] {
    if {![info exists ::QB9_IO($k)]} continue
    set _b [expr {$v * $_p}]; set _L $::env(QB35_IOL)
    if {[lsearch {colin actin topin hostin} $k] >= 0} { set_input_delay -max [expr {$_b + $_L}] -clock qb_clk [get_ports $::QB9_IO($k)] } \
    else { set_output_delay -max [expr {$_b - $_L}] -clock qb_clk [get_ports $::QB9_IO($k)] }
    puts "R37_HUBIO class $k max budget $v P"
}
puts "R37_HUBIO hub clock $_p IO budget at L $::env(QB35_IOL), in2out setup false"
