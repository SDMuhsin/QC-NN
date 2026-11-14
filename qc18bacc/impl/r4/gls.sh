#!/usr/bin/env bash
# R4 zero-delay gate-level simulation of the qb_chip DC netlist (VCS on a tau host) with the chip bench
# (hw/tb/tb_qb_chip.sv +define+QBT_GLS+QBT_VSAIF): program load, E6_s0 val 0 / 1 / 2 streamed back to back, logits
# checked against IntBin2 (logits.txt), SAIF of the whole DUT over [go of image 1, go of image 2).
#   qc18bacc/impl/r4/gls.sh start [host=tau5] [syn_tag=r4_chip] [vec=/tmp/root/qc18bacc/r4/s0t]
#   qc18bacc/impl/r4/gls.sh check [host=tau5] [syn_tag=r4_chip]
# Cells: QC_CELL_V (site.csh), +nospecify +notimingcheck (flow/tsmc65/sim/run_vcs.sh QC_GLS=1); macros: the compiler's
# Verilog models ($QC_MC_OUT/<inst>/<inst>.v of impl/r4/macros.txt).  Remote: $RD/build/sim/gls_<tag>, SAIF
# $RD/gls/<tag>/qb_chip_win12.saif (stays on the host).
set -eu
CMD=${1:?start|check}; H=${2:-tau5}; T=${3:-r4_chip}; V=${4:-/tmp/root/qc18bacc/r4/s0t}
RD=/tmp/ckp908/qc18bacc; G=$RD/gls/$T
case "$CMD" in
start)
    ssh "$H" "mkdir -p $RD/r4vec $G"
    rsync -a "$V/" "$H:$RD/r4vec/"
    ssh "$H" "set -e; cd $RD/repo; N=$RD/build/syn/$T/qb_chip.v; test -f \$N
      . flow/tsmc65/site/sram.sh
      { echo \$N; for i in \$(sed 's/#.*//' qc18bacc/impl/r4/macros.txt | awk 'NF >= 5 {print \$1}'); do echo \$QC_MC_OUT/\$i/\$i.v; done
        echo $RD/repo/qc18bacc/hw/tb/tb_qb_chip.sv; } > $G/gls.f
      export QC_BUILD=$RD/build QC_GLS=1 QC_VCS_OPTS='+define+QBT_GLS+QBT_VSAIF +vcs+initreg+random'
      export QC_SIM_OPTS='+vcs+initreg+0 +prog=$RD/r4vec/prog +n=3 +dir0=$RD/r4vec/img0 +dir1=$RD/r4vec/img1 +dir2=$RD/r4vec/img2 +vsaif=$G/qb_chip_win12.saif'
      export QC_PASS_RE='QB_CHIP_TB GLS.*PASS' QC_FAIL_RE='QB_CHIP_TB.*FAIL|MISMATCH|Error|Fatal'
      setsid nohup flow/tsmc65/sim/run_vcs.sh gls_$T tb_qb_chip $G/gls.f > $G/run.log 2>&1 < /dev/null &
      echo GLS started on \$(hostname -s)" ;;
check)
    S=$RD/build/sim/gls_$T
    ssh "$H" "cat $G/run.log; tail -n 3 $S/vcs.log 2>/dev/null; grep -E 'QB_CHIP|MISMATCH|Error' $S/sim.log 2>/dev/null | head -20; ls -la $G/*.saif 2>/dev/null" ;;
esac
