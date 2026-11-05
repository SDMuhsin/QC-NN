# run without waveform logging (start.chimera_soc.tcl logs every signal)
set StdArithNoWarnings 1
set NumericStdNoWarnings 1
# GeMMX busy/handshake probes + hardware counters (GEMMX_PROBE lines, see gemmx_probe.tcl)
source gemmx_probe.tcl
run -all
gemmx_report
quit -f
