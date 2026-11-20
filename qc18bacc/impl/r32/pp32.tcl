# R32: PT worst path into the pcol s4 / tacc registers (setup of pt_hub.tcl as pt31.tcl)
set f [open $::env(R31_PTHUB)]; set t [read $f]; close $f
eval [string range $t 0 [expr {[string first "if \{\[qc_env QB21_ETM 0\]\}" $t] - 1}]]
foreach pat {s4_reg* tacc_reg*} {
  set eps [get_pins -of [get_cells -quiet *$pat -filter "full_name=~*g_pcol*"] -filter "lib_pin_name==D"]
  set p [get_timing_paths -delay_type max -max_paths 1 -to $eps]
  puts "R32PP $corner $pat worst [format %.3f [get_attribute $p slack]] [get_object_name [get_attribute $p startpoint]] -> [get_object_name [get_attribute $p endpoint]] arrival [format %.3f [get_attribute $p arrival]]"
}
exit
