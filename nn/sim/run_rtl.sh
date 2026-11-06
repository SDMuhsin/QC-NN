#!/usr/bin/env bash
# RTL simulation of ResNet-8 on the KUL GeMMX cluster in the full chimera SoC (Questa, remote tau host).
#   [NN_TRACE=0|1] nn/sim/run_rtl.sh [-H host] [-n images] [-f first] [-t tag] [-l limit_us] [-- build flags]
#   e.g. nn/sim/run_rtl.sh -n 1 -- -DNN_FULL_CHECK          (per-layer byte compare of image 0)
#        nn/sim/run_rtl.sh -H tau5 -n 4 -f 4                 (test images 4..7)
# Steps: compile the network for the chosen test images (nn.compile.main), build the chimera ELF
# (nn/sw/build.sh), split it into memory-island bank images (memisl.py), run tb_chimera_soc with a
# 8 B JTAG stub and a backdoor preload (run_nn.tcl), then decode nn_result from the final memory
# island (memisl.py result) and summarise (summary.py).  Exit 0 = every checksum and logit bit-exact.
# Local results: build/nn_rtl/<tag>/{run.log,result.json,summary.txt}.
# Prereqs: hw/kulcluster/gen.sh + sim/prep_chimera_ws.sh; the remote Questa library is compiled with
# hw/kulcluster/sim/chimera_vsim.sh compile (done here automatically if $R/work is missing).
set -euo pipefail
NN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QCNN=$(cd "$NN/.." && pwd)
HOST=tau1; IMAGES=1; FIRST=0; TAG=""; LIMIT=200000
while getopts "H:n:f:t:l:" o; do
  case $o in H) HOST=$OPTARG;; n) IMAGES=$OPTARG;; f) FIRST=$OPTARG;; t) TAG=$OPTARG;; l) LIMIT=$OPTARG;;
             *) sed -n 2,12p "$0"; exit 2;; esac
done
shift $((OPTIND - 1))
FLAGS="$*"
TAG=${TAG:-img${FIRST}_n${IMAGES}$(echo "$FLAGS" | tr -d ' ' | sed 's/-DNN_/_/g' | tr 'A-Z' 'a-z')}
L=$QCNN/build/nn_rtl/$TAG
R=${KUL_VSIM_DIR:-/tmp/ckp908/qcnn_kul}
QUESTA=${KUL_QUESTA:-/CMC/scripts/siemens.questasim.2022.1_2.csh}
rq() { ssh "$HOST" "tcsh -c 'source $QUESTA >& /dev/null; $*'"; }
mkdir -p "$L"

# 1. network + ELF + memory-island image
echo "--first $FIRST --images $IMAGES $FLAGS" > "$L/cmd.txt"
(cd "$QCNN" && python3 -m nn.compile.main --images "$IMAGES" --first "$FIRST" --check "$IMAGES" --out "$L/gen") > "$L/compile.txt"
NN_GEN=$L/gen NN_BUILD=$L/sw "$NN/sw/build.sh" $FLAGS > "$L/build.txt" 2>&1
python3 "$NN/sim/memisl.py" banks "$L/sw/resnet8.memisl.elf" "$L/run/banks"
mv "$L/run/banks/stub.elf" "$L/run/"
cp "$NN/sim/run_nn.tcl" "$L/run/"

# 2. remote: optimised design (once per host), then the run
if ! ssh "$HOST" "test -d $R/work"; then
  KUL_VSIM_HOST=$HOST KUL_VSIM_DIR=$R "$QCNN/hw/kulcluster/sim/chimera_vsim.sh" compile
fi
# DmaTracing=0: the cluster DMA tracer logs every cycle (100+ MB) and slows the run down
rq "cd $R; test -f work/.nn_opt || (vopt tb_chimera_soc +acc=npr -GDmaTracing=0 -o tb_nn >& vopt_nn.log && touch work/.nn_opt)"
RD=$R/nn/$TAG
# core instruction traces: off by default (core 1 spins in its job loop: GBs), NN_TRACE=0|1 keeps hart 7|both
TR=""
for h in 7 8; do [ "${NN_TRACE:-x}" = 1 ] || { [ "${NN_TRACE:-x}" = 0 ] && [ $h = 7 ]; } || TR="$TR ln -s /dev/null logs/trace_chip_00_hart_0000$h.dasm;"; done
ssh "$HOST" "rm -rf $RD; mkdir -p $RD/logs; cd $RD; $TR true"
rsync -a "$L/run/" "$HOST:$RD/"
echo "[run_rtl] $TAG on $HOST: $(date +%T) start"
rq "cd $RD; setenv NN_SIM_LIMIT $LIMIT; vsim -c -lib $R/work tb_nn -t 1ps -suppress 3009 -suppress 8386 -error 7 +BOOTMODE=0 +PRELMODE=0 +BINARY=$RD/stub.elf -do run_nn.tcl >& run.log; tail -3 run.log" || true
echo "[run_rtl] $TAG on $HOST: $(date +%T) done"

# 3. results
rsync -a "$HOST:$RD/run.log" "$HOST:$RD/out" "$L/"
rsync -a "$HOST:$RD/logs/trace_chip_00_hart_0000[78].dasm" "$L/" 2>/dev/null || true
python3 "$NN/sim/memisl.py" result "$L/sw/resnet8.memisl.elf" "$L/gen/nn_net.h" "$L/out" > "$L/result.json"
python3 "$NN/sim/summary.py" "$L" | tee "$L/summary.txt"; exit ${PIPESTATUS[0]}
