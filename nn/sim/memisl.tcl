# Memory-island backdoor of the ResNet-8 runs (sourced by run_nn.tcl and nn/gls/nn_gls.tcl, cwd = run dir).
#   banks/bank_<i>_<j>.hex  image (nn/sim/memisl.py banks), loaded at time 0 and again at the host's first
#                           instruction; `banks save out` writes the final memory island
#   NN_MARKER="<i> <j> <row>" (env, memisl.py where <elf> nn_result): nn_marker reads nn_result.marker
set MI /tb_chimera_soc/fix/dut/i_memisland_domain/i_memory_island/i_memory_island
proc bank_mem {i j} {
  global MI
  return "$MI/gen_wide_banks\[$i\]/gen_narrow_banks\[$j\]/i_bank/sram"
}
proc banks {cmd dir} {
  for {set i 0} {$i < 2} {incr i} {
    for {set j 0} {$j < 16} {incr j} {
      if {$cmd == "load"} {
        mem load -infile $dir/bank_${i}_${j}.hex -format hex [bank_mem $i $j]
      } else {
        mem save -outfile $dir/bank_${i}_${j}.hex -format hex -wordsperline 1 [bank_mem $i $j]
      }
    }
  }
}
proc nn_marker {} {
  if {![info exists ::env(NN_MARKER)]} { return "" }
  lassign $::env(NN_MARKER) i j row
  return [string tolower [examine -radix hex "[bank_mem $i $j]\[$row\]"]]
}
banks load banks
# CVA6's boot ROM uses a stack just below 0x4801_0000 before the JTAG resume, which clobbers the
# image loaded at time 0 (JTAG preloading writes after it).  Load again when the host commits its
# first instruction at the ELF entry, the same point at which a JTAG preload would be complete.
set pc_commit /tb_chimera_soc/fix/dut/i_cheshire/gen_cva6_cores\[0\]/i_core_cva6/pc_commit
when -label nn_reload "$pc_commit == 32'h48000000" {
  nowhen nn_reload
  banks load banks
  echo "NN_RELOAD $now"
}
