#!/usr/bin/env bash
# QC18-ACC array ablation (QC vs TERNARY vs INT8 PE, same 8x8 array / pipeline / dataflow), one command per step:
#   qc18acc/ablation/run.sh vec            operand streams + numpy reference (vectors.py, GPU 0) -> $L/vec
#   qc18acc/ablation/run.sh rtl            Verilator RTL check of the 8 points (3 tops) -> $L/rtl.txt
#   qc18acc/ablation/run.sh sync           git pull the host-local clones, rsync $L/vec to the hosts
#   qc18acc/ablation/run.sh start <step>   detached remote.sh <step> per variant on its host (syn | sdf | gls | power)
#   qc18acc/ablation/run.sh status <step>  per variant: running / last lines of the step log
#   qc18acc/ablation/run.sh fetch          rsync the hosts' summaries (AB/out, design names only) -> $L/out/<v>
#   qc18acc/ablation/run.sh report         python3 -m qc18acc.ablation.report $L -> qc18acc/results/ablation.md
# Hosts (one variant each): QAB_HOSTS="qc:usask tern:tau5 int8:tau1".  Host work dir /tmp/ckp908/qc18acc/abl
# (remote.sh), clone /tmp/ckp908/qc18acc/repo.  Local dir L = ${QC_LOCAL:-/tmp/root/qc18acc}/ablation.
# QAB_KB=2: the Kb = 2 ablation (v3 geometry): vectors3.py, rtl/qab3.f, host dir .../abl3, local dir .../ablation3,
# report3.py (the "Kb = 2" section of results/ablation.md).
set -euo pipefail
QA=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$QA/../.." && pwd)
KB=${QAB_KB:-1}; export QAB_KB=$KB
RR=/tmp/ckp908/qc18acc
if [ "$KB" = 2 ]; then L=${QC_LOCAL:-/tmp/root/qc18acc}/ablation3; AB=$RR/abl3; VM=vectors3; FL=qab3.f; TP=qab3; XB=1024
else L=${QC_LOCAL:-/tmp/root/qc18acc}/ablation; AB=$RR/abl; VM=vectors; FL=qab.f; TP=qab; XB=512; fi
HOSTS=${QAB_HOSTS:-"qc:usask tern:tau5 int8:tau1"}
pts() { case $1 in qc) echo "qc_L2 qc_L4";; tern) echo "tern_L2 tern_L4";; int8) echo "int8_L2 int8_L4 int8c_L2 int8c_L4";; esac; }
cmd=${1:?}; shift || true
case $cmd in
vec) (cd "$REPO" && CUDA_VISIBLE_DEVICES=0 python3 -m qc18acc.ablation.$VM "$L/vec") ;;
rtl)
  (source /workspace/GanAccelAsic/src/flow/env.sh > /dev/null 2>&1
   SRC=$(sed 's|//.*||' "$QA/rtl/$FL" | awk -v d="$QA/rtl" 'NF { print d "/" $1 }')
   VW="qc:10:20 tern:128:21 int8:512:32"; [ "$KB" = 2 ] && VW="qc:20:20 tern:256:21 int8:1024:32"
   for v in $VW; do IFS=: read -r n wb acc <<< "$v"; mkdir -p "$L/vlt/$n"
     verilator --binary --timing -j 16 -Wno-fatal -Wno-lint -Wno-style +define+TOP=${TP}_top_$n +define+WB=$wb +define+XB=$XB \
       +define+ACC=$acc --top-module tb_qab -Mdir "$L/vlt/$n" $SRC "$QA/tb_qab.sv" -o Vtb > "$L/vlt_$n.log" 2>&1
     for p in $(pts $n); do "$L/vlt/$n/Vtb" +VEC="$L/vec/$p.txt" | grep QAB_RESULT | sed "s/^/rtl $p /"; done
   done) | tee "$L/rtl.txt"
  ! grep -q FAIL "$L/rtl.txt" ;;
sync)
  for hv in $HOSTS; do h=${hv#*:}
    ssh "$h" "cd $RR/repo && git pull -q --ff-only && git log -1 --format='$h %h %s'; mkdir -p $AB/vec $AB/logs"
    rsync -a "$L/vec/" "$h:$AB/vec/"; done ;;
start)
  s=${1:?step}
  for hv in $HOSTS; do v=${hv%%:*}; h=${hv#*:}; a=""; [ "$s" = gls ] || [ "$s" = power ] && a=$(pts "$v")
    ssh "$h" "cd $RR/repo && mkdir -p $AB/logs && (QAB_KB=$KB QAB_ZD=${QAB_ZD:-0} nohup qc18acc/ablation/remote.sh $s $v $a > $AB/logs/${s}${QAB_ZD:+_zd$QAB_ZD}_$v.log 2>&1 < /dev/null &); echo started $s $v on \$(hostname -s)"
  done ;;
status)
  s=${1:?step}
  for hv in $HOSTS; do v=${hv%%:*}; h=${hv#*:}
    ssh "$h" "if pgrep -u \$USER -f '[r]emote.sh $s $v' > /dev/null; then echo '$v $s: RUNNING'; else echo '$v $s: done'; fi; tail -3 $AB/logs/${s}_$v.log 2>/dev/null"
  done ;;
fetch) for hv in $HOSTS; do v=${hv%%:*}; h=${hv#*:}; mkdir -p "$L/out/$v"; rsync -a "$h:$AB/out/" "$L/out/$v/"; done ;;
report) R=report; [ "$KB" = 2 ] && R=report3; (cd "$REPO" && python3 -m qc18acc.ablation.$R "$L" "$REPO/qc18acc/results") ;;
*) sed -n 2,12p "$0"; exit 2 ;;
esac
