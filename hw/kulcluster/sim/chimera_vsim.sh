#!/usr/bin/env bash
# Full-SoC RTL simulation of chimera with TARGET_KULCLUSTER on Questa (remote host, default tau1):
# CVA6 is preloaded over JTAG with the host ELF, which offloads the SNAX GeMM test to the KUL
# cluster (chimera cluster 3) and self-checks. Exit code 0 = PASS.
#   hw/kulcluster/sim/chimera_vsim.sh [compile|run|all]     (default: all)
# Prereqs: hw/kulcluster/gen.sh, hw/kulcluster/sim/prep_chimera_ws.sh, sw/chimera_gemmx/build.sh
set -euo pipefail
KUL_NO_VLT=1 source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
STEP=${1:-all}
HOST=${KUL_VSIM_HOST:-tau1}
R=${KUL_VSIM_DIR:-/tmp/ckp908/qcnn_kul}
QUESTA=${KUL_QUESTA:-/CMC/scripts/siemens.questasim.2022.1_2.csh}
WS=$KUL_BUILD/chimera_ws
ELF=${ELF:-$KUL_BUILD/sw/chimera_gemmx.memisl.elf}
rq() { ssh "$HOST" "tcsh -c 'source $QUESTA >& /dev/null; cd $R; $*'"; }

if [ "$STEP" = compile ] || [ "$STEP" = all ]; then
  VLOG_ARGS='-suppress 2583 -suppress 13314 -suppress 2275 +define+POST_SYNTH +define+HYP_USER_PRELOAD=0 +define+HYP0_PRELOAD_MEM_FILE=\"\"'
  # POST_SYNTH only skips the SDF back-annotation of the (stubbed) HyperRAM model.
  (cd $WS && bender script vsim -t snitch_cluster -t cv32a6_convolve -t cva6 -t rtl -t test -t sim \
      -t kulcluster --vlog-arg="$VLOG_ARGS" 2>/dev/null) \
    | sed -e "s#$WS#$R/chimera_ws#g" -e "s#$KUL_DIR#$R/hw/kulcluster#g" > $KUL_BUILD/compile.chimera_kul.tcl
  CHS=$(cd $WS && bender path cheshire)
  echo "vlog \"${CHS/$WS/$R/chimera_ws}/target/sim/src/elfloader.cpp\" -ccflags \"-std=c++11\"" >> $KUL_BUILD/compile.chimera_kul.tcl
  ssh $HOST "mkdir -p $R/hw/kulcluster $R/sw"
  rsync -a --delete --exclude '.git' --exclude '/.bender/git/db' --exclude 'work/' $WS/ $HOST:$R/chimera_ws/
  rsync -a $KUL_DIR/generated $HOST:$R/hw/kulcluster/
  rsync -a $KUL_BUILD/compile.chimera_kul.tcl $HOST:$R/
  rq "rm -rf work; vlib work >& /dev/null; vsim -c -do \"source compile.chimera_kul.tcl; quit\" >& compile.log; grep -c Error: compile.log; tail -3 compile.log"
fi
if [ "$STEP" = run ] || [ "$STEP" = all ]; then
  rsync -a $ELF $HOST:$R/sw/
  rsync -a $KUL_DIR/sim/run_chimera.tcl $KUL_DIR/sim/gemmx_probe.tcl $HOST:$R/
  B=$R/sw/$(basename $ELF)
  rq "vsim -c tb_chimera_soc -t 1ps -voptargs=+acc=npr -suppress 3009 -suppress 8386 -error 7 +BOOTMODE=0 +PRELMODE=0 +BINARY=$B -do run_chimera.tcl >& run.log; grep -i \"exit code\\|error\\|fatal\\|KUL\" run.log | head -20; tail -5 run.log"
  # cycle breakdown of the GeMM (hardware probes + core-0 trace) -> $KUL_BUILD/vsim_run/
  mkdir -p $KUL_BUILD/vsim_run
  rsync -a $HOST:$R/run.log $HOST:$R/logs/trace_chip_00_hart_00007.dasm $KUL_BUILD/vsim_run/
  SA=$KUL_BUILD/run_snax-gemmx-matmul-perf/gemmx_perf.log   # from run_standalone.sh, if run
  python3 $KUL_DIR/scripts/gemmx_cycles.py --run-log $KUL_BUILD/vsim_run/run.log \
    --trace $KUL_BUILD/vsim_run/trace_chip_00_hart_00007.dasm --elf $ELF \
    $([ -f $SA ] && echo --standalone $SA) -o $KUL_BUILD/vsim_run/gemmx_cycles.txt
fi
