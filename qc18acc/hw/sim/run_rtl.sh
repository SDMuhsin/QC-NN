#!/usr/bin/env bash
# QC18-ACC full-network RTL simulation in one command (from anywhere in the repo, on the local machine):
#   qc18acc/hw/sim/run_rtl.sh [host=usask] [first_image=0] [n_images=4]
# 1. export the memory images + expected per-pass maps / logits (compiler + golden model, local GPU / CPU)
# 2. rsync them to <host>:$QC_RDIR/export_rtl (host-local disk)
# 3. on <host>: git pull the host-local clone $QC_RDIR/repo, VCS RTL simulation via flow/tsmc65/sim/run_vcs.sh
#    (build dir $QC_RDIR/build), testbench qa_tb with +DIR / +IMG0 / +NIMG
# 4. fetch sim.log to $QC_LOCAL/rtl_sim.log, print the summary and the measured-vs-model cycle table
# Environment: QC_CKPT (default /tmp/root/qc18/final/s8kd_s0/best.pt), QC_RDIR (default /tmp/ckp908/qc18acc),
#   QC_LOCAL (default /tmp/root/qc18acc), QC_SKIP_EXPORT=1 (reuse $QC_LOCAL/export_rtl), QC_TAG (default qc18acc_rtl),
#   QC_MINI=1 (random mini program of qc18acc/hw/tb/mini.py instead of the s8kd network).
set -eu
HOST=${1:-usask}; IMG0=${2:-0}; NIMG=${3:-4}
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
CKPT=${QC_CKPT:-/tmp/root/qc18/final/s8kd_s0/best.pt}
RDIR=${QC_RDIR:-/tmp/ckp908/qc18acc}
LOC=${QC_LOCAL:-/tmp/root/qc18acc}
TAG=${QC_TAG:-qc18acc_rtl}
EXP=$LOC/export_rtl
cd "$REPO"
if [ "${QC_SKIP_EXPORT:-0}" != 1 ]; then
    rm -rf "$EXP"
    ids=$(seq -s, "$IMG0" $((IMG0 + NIMG - 1)))
    if [ "${QC_MINI:-0}" = 1 ]; then
        python3 -m qc18acc.hw.tb.mini "$EXP" --images $((IMG0 + NIMG))
    else
        python3 -m qc18acc.compile.main --ckpt "$CKPT" --n 0 --literal 0 --export "$EXP" --images "$ids" | tail -3
    fi
fi
awk '$1 == "pass" { print $3 }' "$EXP/program.txt" > "$EXP/names.txt"
ssh "$HOST" "mkdir -p $RDIR/export_rtl $RDIR/build"
rsync -a --delete "$EXP/" "$HOST:$RDIR/export_rtl/"
ssh "$HOST" "cd $RDIR/repo && git pull -q --ff-only && git log -1 --format='%h %s' &&
  QC_BUILD=$RDIR/build QC_SIM_OPTS='+DIR=$RDIR/export_rtl +IMG0=$IMG0 +NIMG=$NIMG' QC_PASS_RE='RESULT PASS' \
  QC_FAIL_RE='RESULT FAIL|MISMATCH|Error|Fatal' \
  flow/tsmc65/sim/run_vcs.sh $TAG qa_tb qc18acc/hw/rtl/qc18acc.f qc18acc/hw/tb/tb.f" || true
scp -q "$HOST:$RDIR/build/sim/$TAG/sim.log" "$LOC/rtl_sim.log" || { scp -q "$HOST:$RDIR/build/sim/$TAG/vcs.log" "$LOC/rtl_vcs.log"; grep -E "Error|error" "$LOC/rtl_vcs.log" | head; exit 1; }
grep -E "^(TB|IMAGE|PERF|RESULT|MAP)|MISMATCH|Error" "$LOC/rtl_sim.log" | head -40
python3 -m qc18acc.hw.sim.cycles "$LOC/rtl_sim.log" "$EXP" "$IMG0"
