# R36 PrimeTime chip SDC = impl/r35/pt_top_sdc.tcl (IO delays +- QB35_TOPL, EMA fix) + QB36_RSTFP [1]: false path from the
# asynchronous reset port rst_n (as impl/r36/top_sdc.tcl for OpenROAD).
source [file normalize [file dirname [info script]]/../r35/pt_top_sdc.tcl]
if {[qc_env QB36_RSTFP 1]} { set_false_path -from [get_ports rst_n] }
