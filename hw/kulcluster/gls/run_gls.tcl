# Gate-level run of chimera + KUL cluster netlist (no waveform logging), see gls.sh
set StdArithNoWarnings 1
set NumericStdNoWarnings 1
source gls_probe.tcl
# GLS_STOP=<time> (env): stop there instead of at the end of the test (debug)
if {[info exists ::env(GLS_STOP)]} { run $::env(GLS_STOP) } else { run -all }
gemmx_report
quit -f
