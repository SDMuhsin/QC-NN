# Questa run script of the ResNet-8 RTL simulation (nn/sim/run_rtl.sh, cwd = the run directory).
#   banks/bank_<i>_<j>.hex  memory-island image (nn/sim/memisl.py banks), loaded at time 0
#   out/bank_<i>_<j>.hex    memory island at the end (nn_result is decoded from it)
# GeMMX busy edges are logged as "NN_PROBE <signal> <value> <time_ps>" (cheap: a few per conv).
set StdArithNoWarnings 1
set NumericStdNoWarnings 1
set MI /tb_chimera_soc/fix/dut/i_memisland_domain/i_memory_island/i_memory_island
proc banks {cmd dir} {
  global MI
  for {set i 0} {$i < 2} {incr i} {
    for {set j 0} {$j < 16} {incr j} {
      set m "$MI/gen_wide_banks\[$i\]/gen_narrow_banks\[$j\]/i_bank/sram"
      if {$cmd == "load"} {
        mem load -infile $dir/bank_${i}_${j}.hex -format hex $m
      } else {
        mem save -outfile $dir/bank_${i}_${j}.hex -format hex -wordsperline 1 $m
      }
    }
  }
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

proc inst {du} { lindex [lindex [find instances -recursive -bydu $du] 0] 0 }
set bg [inst KULCluster_BlockGemm]
set st [inst KULCluster_snax_streamer_gemmX_Streamer]
foreach {name sig} [list gemm_busy $bg/cstate simd_busy [file dirname $bg]/simd/io_busy_o str_busy $st/cstate] {
  when -label nn_$name "$sig'event" "echo \"NN_PROBE $name \[examine -radix unsigned $sig\] \$now\""
}
# run in chunks; every chunk logs both cluster cores' PCs ("NN_PC <time_ps> <pc core0> <pc core1>")
set cores [find instances -recursive -bydu KULCluster_snitch]
onfinish stop
set limit [expr {[info exists ::env(NN_SIM_LIMIT)] ? $::env(NN_SIM_LIMIT) : 200000}]
set chunk [expr {[info exists ::env(NN_SIM_CHUNK)] ? $::env(NN_SIM_CHUNK) : 100}]
for {set t 0} {$t < $limit} {incr t $chunk} {
  run ${chunk}us
  set pcs {}
  foreach c $cores { lappend pcs [examine -radix hex [lindex $c 0]/pc_q] }
  echo "NN_PC $now $pcs"
  if {[lindex [runStatus -full] 0] == "break"} { break }
  if {[string match "*x*" $pcs]} { echo "NN_HANG pc is X"; break }
}
echo "NN_SIM_END $now"
file mkdir out
# TCDM banks (debug: -DNN_STOP_AFTER=<step> freezes core 0 after that step; sim/tcdm_check.py)
set ti 0
foreach b [find instances -recursive -bydu KULCluster_tc_sram] {
  set b [lindex $b 0]
  if {[string match "*gen_banks*i_data_mem*" $b]} {
    regexp {gen_banks\[(\d+)\]} $b -> k
    mem save -outfile out/tcdm_$k.hex -format hex -wordsperline 1 $b/sram
  }
}
# not finished: dump the KUL cluster's AXI master handshakes (where a hang sits)
if {[lindex [runStatus -full] 0] != "break"} {
  set ad [lindex [lindex [find instances -recursive -bydu chimera_cluster_adapter] end] 0]
  foreach {p q} {clu_narrow_out_req_i clu_narrow_out_resp_o clu_wide_out_req_i clu_wide_out_resp_o \
                 narrow_out_req_o narrow_out_resp_i wide_out_req_o wide_out_resp_i} {
    foreach f {ar_valid ar.addr ar.id ar.len ar.size r_ready aw_valid aw.addr w_valid b_ready} {
      catch {echo "NN_AXI $p.$f [examine -radix hex $ad/$p.$f]"}
    }
    foreach f {ar_ready r_valid r.id r.last aw_ready w_ready b_valid} {
      catch {echo "NN_AXI $q.$f [examine -radix hex $ad/$q.$f]"}
    }
  }
}
banks save out
quit -f
