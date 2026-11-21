# R37 QB35_IO_TCL for the hub (impl/r35/hold35.tcl; results/r37.md sec. 9): clock at the chip period QB35_PER, the run's hub
# IO budget (impl/r9b/sdc.py hub_io.tcl, QB37_HUBIO) at the PT-measured tt p50 insertion delay QB35_IOL, in2out feed-through
# paths false for setup (timed at chip level, as the pt37 sign-off), and per-port extra tightening QB37_SSX (file of
# "in|out <port> <X ns>", from impl/r37 ssx: X = tt slack + (0.05 - ss slack) / 1.4) so a tt-only repair also closes ss.
set _p $::env(QB35_PER)
create_clock -name qb_clk -period $_p -waveform [list 0 [expr {$_p / 2.0}]] [get_ports clk]
set_clock_uncertainty -setup 0.25 [get_clocks qb_clk]; set_clock_uncertainty -hold 0.05 [get_clocks qb_clk]
set_propagated_clock [all_clocks]
source $::env(QB37_HUBIO)
qb9_io_apply $_p $::env(QB35_IOL)
set_false_path -setup -from [all_inputs] -to [all_outputs]
# budget fractions of impl/r9b/sdc.py (B)
array set _fr {colin 0.27 colout 0.20 colnorth 0.55 actout 0.30 actin 0.40 topin 0.40 topout 0.40 hostin 0.30}
array set _cls {}
foreach k [array names ::QB9_IO] { foreach p $::QB9_IO($k) { set _cls($p) $k } }
# QB37_FR "<class> <fraction> ...": budget re-split of whole classes (e.g. actout 0.26 with the act QB7_DIN 0.74: the output delay is the external share)
foreach {k v} [qc_env QB37_FR ""] { set _fr($k) $v }
foreach {k v} [qc_env QB37_FR ""] {
    if {![info exists ::QB9_IO($k)]} continue
    set _b [expr {$v * $_p}]; set _L $::env(QB35_IOL)
    if {[lsearch {colin actin topin hostin} $k] >= 0} { set_input_delay -max [expr {$_b + $_L}] -clock qb_clk [get_ports $::QB9_IO($k)] } \
    else { set_output_delay -max [expr {$_b - $_L}] -clock qb_clk [get_ports $::QB9_IO($k)] }
    puts "R37_HUBIO class $k max budget $v P"
}
set _n 0
if {[qc_env QB37_SSX ""] ne ""} {
    set f [open $::env(QB37_SSX)]
    foreach ln [split [read $f] "\n"] {
        if {[llength $ln] < 3} continue
        lassign $ln d p x
        if {![info exists _cls($p)]} { puts "R37_HUBIO no class for $p"; continue }
        set b [expr {$_fr($_cls($p)) * $_p}]
        if {$d eq "in"} { set_input_delay -max [expr {$b + $::env(QB35_IOL) + $x}] -clock qb_clk [get_ports $p] } \
        else { set_output_delay -max [expr {$b - $::env(QB35_IOL) + $x}] -clock qb_clk [get_ports $p] }
        incr _n
    }
    close $f
}
puts "R37_HUBIO hub clock $_p IO budget at L $::env(QB35_IOL), in2out setup false, $_n ports tightened"
