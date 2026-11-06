# Questa script of the gate-level ResNet-8 run (nn/gls/run_gls.sh, cwd = the run directory): chimera RTL with
# the KUL cluster as DC netlist.  Memory-island backdoor as in the RTL run (memisl.tcl); GeMMX busy edges and
# counters from hw/kulcluster/gls/gls_probe.tcl (GEMMX_PROBE lines, binary values, so X shows up).
# Environment:
#   NN_MARKER    "<i> <j> <row>" of nn_result.marker; the run ends when it reads 0xdead.... (-DNN_STOP_AFTER)
#   NN_SAIF_CALL n: SAIF of the whole netlist over GeMMX call n (1-based), from the rising to the falling
#                edge of BlockGemm io_busy_o -> layer.saif (stays on the server: it names kit cells)
#   NN_SAIF_WIN  "<t0_us> <t1_us>": SAIF over that fixed time window instead (e.g. inside a residual add, from the
#                RTL run's timing; the zero-delay run is cycle-exact with it)
#   NN_SIM_LIMIT / NN_SIM_CHUNK  run limit / poll interval in us (default 5000 / 10)
# At the end: out/bank_<i>_<j>.hex (memory island), out/macro_<k>.mem (the 32 TCDM macros, binary, tcdm_macro.py).
set StdArithNoWarnings 1
set NumericStdNoWarnings 1
source memisl.tcl
source gls_probe.tcl
onfinish stop

set nn_call 0
if {[info exists ::env(NN_SAIF_CALL)]} {
  when -label nn_saif "$gx_bg/io_busy_o'event" {
    if {[examine -radix binary $gx_bg/io_busy_o] == "1"} {
      if {[incr nn_call] == $::env(NN_SAIF_CALL)} {
        echo "NN_SAIF_ON call $nn_call $now"
        power add -in -out -inout -internal -nocellnet -r $gx_top/*
      }
    } elseif {$nn_call == $::env(NN_SAIF_CALL)} {
      echo "NN_SAIF_OFF call $nn_call $now"
      power report -all -bsaif layer.saif   ;# -all: also the nets that never toggled
      nowhen nn_saif
    }
  }
}

if {[info exists ::env(NN_SAIF_WIN)]} {
  lassign $::env(NN_SAIF_WIN) w0 w1
  run ${w0}us
  echo "NN_SAIF_ON win 0 $now"
  power add -in -out -inout -internal -nocellnet -r $gx_top/*
  run [expr {$w1 - $w0}]us
  echo "NN_SAIF_OFF win 0 $now"
  power report -all -bsaif layer.saif
}
set limit [expr {[info exists ::env(NN_SIM_LIMIT)] ? $::env(NN_SIM_LIMIT) : 5000}]
set chunk [expr {[info exists ::env(NN_SIM_CHUNK)] ? $::env(NN_SIM_CHUNK) : 10}]
set t0 [clock seconds]
for {set t 0} {$t < $limit} {incr t $chunk} {
  run ${chunk}us
  if {$t % 100 == 0} { echo "NN_WALL $now [expr {[clock seconds] - $t0}] s" }
  if {[lindex [runStatus -full] 0] == "break"} { break }
  if {[string match "dead*" [nn_marker]]} { echo "NN_STOPPED [nn_marker] $now"; break }
}
echo "NN_SIM_END $now wall [expr {[clock seconds] - $t0}] s"
gemmx_report
file mkdir out
# (find -bydu does not see `celldefine macro models: select the macros under the data memory by name)
foreach m [find instances -r $gx_top/i_cluster/i_snitch_data_mem/*] {
  if {[lindex $m 1] ne "(kul_rf_512x64m4)"} { continue }
  set m [lindex $m 0]
  if {[regexp {gen_banks_(\d+)__} $m -> k]} {
    mem save -outfile out/macro_$k.mem -format binary -wordsperline 1 $m/mem
  }
}
banks save out
quit -f
