# R37 QB37_HPRE_TCL for the act (impl/r35/hold35.tcl hook, results/r37.md sec. 9): impl/r37/inbuf37.tcl input-port buffers,
# then the output hold windows loosened by the hold margin QB35_HOLD_M (output -min = -L + margin), so the margin acts on
# reg2reg / in2reg only and the output hold requirement stays exactly the sign-off one (ECO 1 at margin 0.05 put a
# chain on every act output; ECO 1 / 2 at margin 0-0.02 left reg2reg -0.02 after legalisation + re-route).
source [file dirname $::env(QB37_HPRE_TCL)]/inbuf37.tcl   ;# (info script is not usable in OpenROAD)
set _m [qc_env QB37_OOFF [qc_env QB35_HOLD_M 0.0]]   ;# QB37_OOFF: offset < margin leaves the outputs (margin - offset)
set_output_delay -min [expr {-$::env(QB35_IOL) + $_m}] -clock qb_clk [all_outputs]
puts "R37_ACTPRE output -min delay = -L + $_m on [llength [all_outputs]] outputs"
