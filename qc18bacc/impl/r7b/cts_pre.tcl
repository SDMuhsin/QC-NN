# PRE_CTS_TCL of impl/r7b/chip.cfg: impl/r6c/cts_pre.tcl (spread procedures on restart, QB_ICG) + blklat.tcl (no-op
# when db/place.sdc already has no block clk latency)
source $::QB_R6C/cts_pre.tcl
source $::QB_R7B/blklat.tcl
