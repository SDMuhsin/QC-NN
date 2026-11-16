# R8a PT hook: full worst path to each endpoint pin listed in $env(QB_EPS) (space separated) -> rpt/pt_<corner>_eps.rpt
set xf [open $out/rpt/pt_${corner}_eps.rpt w]
foreach e $::env(QB_EPS) {
    set ep [get_pins -quiet $e]
    if {![sizeof_collection $ep]} { puts $xf "#### $e: no pin"; continue }
    redirect -variable rt { report_timing -to $ep -nosplit -input_pins -significant_digits 3 }
    puts $xf "#### $e"; puts $xf $rt
}
close $xf
