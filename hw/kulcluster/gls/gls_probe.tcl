# Gate-level twin of sim/gemmx_probe.tcl: the same GEMMX_PROBE lines (scripts/gemmx_cycles.py
# format), taken from nets that survive synthesis in the DC netlist:
#   gemm_busy  KULCluster_BlockGemm io_busy_o            (= its cstate_reg, sBUSY)
#   simd_busy  KULCluster_PipelinedRescaleSIMD io_busy_o (cstate_reg)
#   str_busy   KULCluster_snax_streamer_gemmX_Streamer cstate (cstate_reg)
#   counters   io_performance_counter / performance_counter (the perf counter flops' Q nets)
# The MAC-array handshake nets (gemm_a_b_input_fire / add_c_fire) are optimised away by DC.
# Values are printed in binary, so an X/Z on a busy net shows up in the log (gls_summary.py
# flags it); X on the cluster's AXI handshakes is checked by gls_xcheck.sv.
proc gls_inst {du} {
  set r [find instances -recursive -bydu $du]
  if {[llength $r] == 0} { echo "GLS_ERROR missing $du"; return "" }
  return [lindex [lindex $r 0] 0]
}
set gx_top  [gls_inst KULCluster_snax_KUL_cluster_wrapper]
set gx_bg   [gls_inst KULCluster_BlockGemm]
set gx_simd [gls_inst KULCluster_PipelinedRescaleSIMD]
set gx_str  [gls_inst KULCluster_snax_streamer_gemmX_Streamer]
set gx_xchk [gls_inst gls_xcheck]
echo "GLS_INFO cluster $gx_top"
set gx_sigs [list \
  gemm_busy $gx_bg/io_busy_o \
  simd_busy $gx_simd/io_busy_o \
  str_busy  $gx_str/cstate ]
foreach {name sig} $gx_sigs {
  when -label gx_$name "$sig'event" "echo \"GEMMX_PROBE $name \[examine -radix binary $sig\] \$now\""
}
# clock period sample at the first GeMM start (same as the RTL probe)
set gx_nclk 0
when -label gx_clk "$gx_bg/io_busy_o == 1" {
  nowhen gx_clk
  when -label gx_clk2 "$gx_bg/clock'event and $gx_bg/clock == 1" {
    echo "GEMMX_PROBE clk_edge 1 $now"
    if {[incr gx_nclk] >= 2} { nowhen gx_clk2 }
  }
}
onfinish stop
proc gls_ctr {sig} {
  set v [examine -radix binary $sig]
  if {[regexp {[xXzZ]} $v]} { return "X($v)" }
  return [examine -radix unsigned $sig]
}
proc gemmx_report {} {
  global gx_bg gx_simd gx_str gx_xchk
  echo "GLS_XCHECK cycles_checked [examine -radix unsigned $gx_xchk/nchk] x_errors [examine -radix unsigned $gx_xchk/nerr]"
  echo "GEMMX_PROBE ctr_gemm   [gls_ctr $gx_bg/io_performance_counter] end"
  echo "GEMMX_PROBE ctr_simd   [gls_ctr $gx_simd/io_performance_counter] end"
  echo "GEMMX_PROBE ctr_stream [gls_ctr $gx_str/performance_counter] end"
}
