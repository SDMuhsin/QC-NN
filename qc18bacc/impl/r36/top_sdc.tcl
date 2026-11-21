# R36 OpenROAD top SDC = impl/r35/top_sdc.tcl with the chip IO delays shifted by the top clock latency QB35_TOPL
# [0] exactly as impl/r35/pt_top_sdc.tcl does for PrimeTime (inputs 0.2 P + L, outputs 0.2 P - L): one IO model for
# P&R and sign-off (R35a bug 8).
source [file normalize $::env(QC_FLOW)/../../qc18bacc/impl/r35/top_sdc.tcl]
set _L [expr {[info exists ::env(QB35_TOPL)] ? $::env(QB35_TOPL) : 0.0}]
set_input_delay [expr {0.2 * $_p + $_L}] -clock qb_clk $_in
set_output_delay [expr {0.2 * $_p - $_L}] -clock qb_clk [all_outputs]
# QB36_RSTFP [1]: the chip reset input is asynchronous (recovery / removal from the pin are not a synchronous budget);
# it is false-pathed from the port, as in PT (impl/r36/pt_top_sdc.tcl).  r36_f1 post-CTS: worst setup was rst_n -> seq
# kq_reg recovery through two hub feedthroughs at input delay 0.2 P + L.
if {![info exists ::env(QB36_RSTFP)] || $::env(QB36_RSTFP)} { set_false_path -from [get_ports rst_n] }
