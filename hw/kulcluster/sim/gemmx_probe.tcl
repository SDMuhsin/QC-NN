# Hardware-side measurement of the KUL cluster's GeMMX run (sourced by run_chimera.tcl).
# Logs every change of the GeMM core / SIMD / streamer busy state and of the MAC-array input
# handshakes as "GEMMX_PROBE <signal> <value> <time_ps>", plus the hardware performance
# counters at the end of the simulation. scripts/gemmx_cycles.py turns this into cycle counts.
proc gemmx_inst {du} {
  set r [find instances -recursive -bydu $du]
  if {[llength $r] == 0} { echo "GEMMX_PROBE missing $du"; return "" }
  return [lindex [lindex $r 0] 0]
}
set gx_bg  [gemmx_inst KULCluster_BlockGemm]
set gx_str [gemmx_inst KULCluster_snax_streamer_gemmX_Streamer]
set gx_simd [file dirname $gx_bg]/simd
set gx_sigs [list \
  gemm_busy   $gx_bg/cstate \
  ab_fire     $gx_bg/gemm_a_b_input_fire \
  addc_fire   $gx_bg/add_c_fire \
  simd_busy   $gx_simd/io_busy_o \
  str_busy    $gx_str/cstate ]
foreach {name sig} $gx_sigs {
  when -label gx_$name "$sig'event" "echo \"GEMMX_PROBE $name \[examine -radix unsigned $sig\] \$now\""
}
# one clock period sample at the first GeMM start
when -label gx_clk "$gx_bg/cstate == 1" {
  nowhen gx_clk
  set gx_t0 $now
  when -label gx_clk2 "$gx_bg/clock'event and $gx_bg/clock == 1" {
    echo "GEMMX_PROBE clk_edge 1 $now"
    if {[incr gx_nclk] >= 2} { nowhen gx_clk2 }
  }
}
set gx_nclk 0
onfinish stop
proc gemmx_report {} {
  global gx_bg gx_simd gx_str
  echo "GEMMX_PROBE ctr_gemm   [examine -radix unsigned $gx_bg/performance_counter] end"
  echo "GEMMX_PROBE ctr_simd   [examine -radix unsigned $gx_simd/performance_counter] end"
  echo "GEMMX_PROBE ctr_stream [examine -radix unsigned $gx_str/performance_counter] end"
}
