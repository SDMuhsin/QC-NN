#!/usr/bin/env bash
# Gate-level simulation of one ResNet-8 layer in the full chimera SoC (Questa, remote tau host): chimera RTL
# with the KUL cluster as DC netlist (hw/kulcluster/gls), running the same ELF as the RTL run up to and
# including the chosen step; core 0 checks that step's output (Fletcher checksum vs the PyTorch int8
# reference) and freezes (-DNN_STOP_AFTER), the TCDM is dumped and the layer output compared byte by byte.
#   nn/gls/run_gls.sh [-H host] [-m zd|sdf] [-c clk_ps] [-s step] [-f image] [-t tag]
#     -m zd   zero delay (+nospecify +notimingchecks, macros in unit-delay mode)      (default)
#     -m sdf  tt SDF of hw/kulcluster/gls/gls.sh sdf (ideal-clock view), timing checks on
#     -c      cluster clock period in ps (default 2000 = the RTL run's; sdf needs >= the tt fmax period)
#     -s      step name (default conv1); its GeMMX call is also the SAIF window (layer.saif on the host)
#     -w "<t0_us> <t1_us>"  SAIF over this time window instead (for a step without GeMMX, e.g. -s add1)
# Env: KUL_GLS_SYN (netlist run dir), KUL_GLS_DIR (remote GLS root: <mode>/work = compiled library, made
#      with `KUL_GLS_DIR=.. KUL_GLS_SYN=.. hw/kulcluster/gls/gls.sh compile <mode>`), SDF via gls.sh sdf.
# Local results: build/nn_gls/<tag>/{run.log,result.json,check.txt,summary.txt}.  Exit 0 = layer bit-exact.
set -euo pipefail
NN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QCNN=$(cd "$NN/.." && pwd)
HOST=tau1; MODE=zd; CLK=2000; STEP=conv1; FIRST=0; TAG=""; WIN=""
while getopts "H:m:c:s:f:t:w:" o; do
  case $o in H) HOST=$OPTARG;; m) MODE=$OPTARG;; c) CLK=$OPTARG;; s) STEP=$OPTARG;; f) FIRST=$OPTARG;;
             t) TAG=$OPTARG;; w) WIN=$OPTARG;; *) sed -n 2,16p "$0"; exit 2;; esac
done
TAG=${TAG:-${STEP}_${MODE}_${CLK}ps}
L=$QCNN/build/nn_gls/$TAG
R=${KUL_GLS_DIR:-/tmp/ckp908/qcnn_nngls}
QUESTA=${KUL_QUESTA:-/CMC/scripts/siemens.questasim.2022.1_2.csh}
SDFI=$R/sdfgen/KULCluster_snax_KUL_cluster_wrapper_tt_idealclk.sdf.gz
rq() { ssh "$HOST" "tcsh -c 'source $QUESTA >& /dev/null; $*'"; }

# step index and GeMMX call number of the layer (nn/compile/lower.py ORDER: one GeMMX call per conv)
read -r IDX CALL < <(cd "$QCNN" && python3 -c "
from nn.compile.lower import ORDER
i = ORDER.index('$STEP'); print(i, sum(s.startswith('conv') for s in ORDER[:i + 1]))")
"$NN/sim/prep.sh" "$L" "$FIRST" 1 -DNN_STOP_AFTER="$IDX"
cp "$NN/gls/nn_gls.tcl" "$QCNN/hw/kulcluster/gls/gls_probe.tcl" "$L/run/"

RD=$R/$MODE/nn_$TAG
ssh "$HOST" "test -d $R/$MODE/work" || { echo "no GLS library $R/$MODE/work (gls.sh compile $MODE)"; exit 1; }
ssh "$HOST" "rm -rf $RD; mkdir -p $RD/logs; cd $RD; for h in 7 8; do ln -s /dev/null logs/trace_chip_00_hart_0000\$h.dasm; done"
rsync -a "$L/run/" "$HOST:$RD/"
GX=/tb_chimera_soc/fix/dut/i_cluster_domain/i_chimera_cluster_kulcluster/i_test_cluster
# netlist nets for the SAIF (recursive), probe modules, the memory-island SRAMs (backdoor), CVA6 (reload
# trigger), the TCDM macro arrays (dump)
ACC="+acc=n+$GX. +acc=n+KULCluster_BlockGemm+KULCluster_PipelinedRescaleSIMD+KULCluster_snax_streamer_gemmX_Streamer"
ACC="$ACC +acc=rn+gls_xcheck +acc=npr+tc_sram +acc=npr+cva6 +acc=rc+kul_rf_512x64m4"
if [ "$MODE" = zd ]; then
  VOPT="+nospecify +notimingchecks $ACC"; SDFOPT=""
else
  VOPT="$ACC"; SDFOPT="-sdftyp $GX=$SDFI -suppress 16107"   # 16107: see hw/kulcluster/gls/gls.sh
fi
MK=$(cat "$L/run/marker.txt")
echo "[run_gls] $TAG ($STEP = step $IDX, GeMMX call $CALL) on $HOST: $(date +%T) start"
rq "cd $RD; setenv NN_MARKER \"$MK\"; $([ -n "$WIN" ] && echo "setenv NN_SAIF_WIN \"$WIN\";" || echo "setenv NN_SAIF_CALL $CALL;") vsim -c -lib $R/$MODE/work tb_chimera_soc gls_bind -t 1ps -voptargs=\\\"$VOPT\\\" $SDFOPT -G/tb_chimera_soc/fix/vip/ClkPeriodClu=$CLK -suppress 3009 -suppress 8386 -error 7 +BOOTMODE=0 +PRELMODE=0 +BINARY=$RD/stub.elf -do nn_gls.tcl >& run.log; tail -2 run.log" || true
echo "[run_gls] $TAG on $HOST: $(date +%T) done"

rsync -a "$HOST:$RD/run.log" "$HOST:$RD/out" "$L/"
ssh "$HOST" "ls -la $RD/layer.saif" || true
python3 "$NN/sim/memisl.py" result "$L/sw/resnet8.memisl.elf" "$L/gen/nn_net.h" "$L/out" > "$L/result.json"
python3 "$NN/gls/tcdm_macro.py" "$L"
(cd "$QCNN" && python3 -m nn.sim.tcdm_check "$L" "$STEP") | tee "$L/check.txt"
python3 "$NN/gls/summary.py" "$L" "$STEP" ${NN_GLS_RTL:+--rtl "$NN_GLS_RTL"} | tee "$L/summary.txt"; exit ${PIPESTATUS[0]}
