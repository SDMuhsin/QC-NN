# Questa script of one ablation gate-level run (qcacc/ablation/remote.sh gls): SAIF of the whole netlist over the
# DUT busy window (rising to falling edge of /tb_abl/busy) -> abl.saif (stays on the host: it names kit cells).
set StdArithNoWarnings 1
set NumericStdNoWarnings 1
onfinish stop
set abl_on 0
when -label abl_saif {/tb_abl/busy'event} {
  if {[examine -radix binary /tb_abl/busy] == "1"} {
    echo "ABL_SAIF_ON $now"
    set abl_on 1
    power add -in -out -inout -internal -nocellnet -r /tb_abl/dut/*
  } elseif {$abl_on} {
    echo "ABL_SAIF_OFF $now"
    power report -all -bsaif abl.saif
    nowhen abl_saif
  }
}
run -all
quit -f
