#!/usr/bin/env bash
# QC18-ACC v3 (Kb = 2) full-network RTL simulation in one command (v2: hw/sim/run_rtl.sh) (from anywhere in the repo, on the local machine):
#   qc18acc/hw3/sim/run_rtl.sh [host=usask] [first_image=0] [n_images=4]
# 1. export the memory images + expected per-pass maps / logits (compiler + golden model, local GPU / CPU)
# 2. rsync them to <host>:$QC_RDIR/export_rtl (host-local disk)
# 3. on <host>: git pull the host-local clone $QC_RDIR/repo, VCS RTL simulation via flow/tsmc65/sim/run_vcs.sh
#    (build dir $QC_RDIR/build), testbench qa_tb with +DIR / +IMG0 / +NIMG
# 4. fetch sim.log to $QC_LOCAL/rtl_sim.log, print the summary and the measured-vs-model cycle table
# Environment: QC_CKPT (default /tmp/root/qc18/final/s8kd_s0/best.pt), QC_RDIR (default /tmp/ckp908/qc18acc),
#   QC_LOCAL (default /tmp/root/qc18acc3), QC_SKIP_EXPORT=1 (reuse $QC_LOCAL/export_rtl), QC_TAG (default qc18acc3_rtl),
#   QC_MINI=1 (random mini program of qc18acc/hw3/tb/mini.py instead of the s8kd network),
#   QC_TECH=1 (RTL with the TSMC 65 nm macros: hw3/tech/qc18acc_tech.f + the host's macro Verilog models
#   (QC_MC_OUT of flow/tsmc65/site/sram.sh) + the tcbn65gplus cell models (macro clock gates), +define+QA_TECH,
#   zero delay; default tag qc18acc3_rtl_tech).
set -eu
HOST=${1:-usask}; IMG0=${2:-0}; NIMG=${3:-4}
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
CKPT=${QC_CKPT:-/tmp/root/qc18/final/s8kd_s0/best.pt}
RDIR=${QC_RDIR:-/tmp/ckp908/qc18acc}
LOC=${QC_LOCAL:-/tmp/root/qc18acc3}
TECH=${QC_TECH:-0}
FL="qc18acc/hw3/rtl/qc18acc.f"; VOPTS=""; LOG=rtl_sim; TAG=${QC_TAG:-qc18acc3_rtl}
if [ "$TECH" = 1 ]; then
    TAG=${QC_TAG:-qc18acc3_rtl_tech}
    FL="qc18acc/hw3/tech/qc18acc_tech.f qc18acc/hw3/tech/macros_sim.f"; LOG=rtl_tech_sim
    VOPTS="+define+QA_TECH -v \$QC_CELL_V +nospecify +notimingcheck"   # cell models: macro clock gates (CKLNQD)
fi
EXP=$LOC/export_rtl
cd "$REPO"
if [ "${QC_SKIP_EXPORT:-0}" != 1 ]; then
    rm -rf "$EXP"
    ids=$(seq -s, "$IMG0" $((IMG0 + NIMG - 1)))
    if [ "${QC_MINI:-0}" = 1 ]; then
        python3 -m qc18acc.hw3.tb.mini "$EXP" --images $((IMG0 + NIMG))
    else
        python3 -m qc18acc.compile3.main --ckpt "$CKPT" --n 0 --literal 0 --export "$EXP" --images "$ids" | tail -3
    fi
fi
awk '$1 == "pass" { print $3 }' "$EXP/program.txt" > "$EXP/names.txt"
ssh "$HOST" "mkdir -p $RDIR/export_rtl3 $RDIR/build"
rsync -a --delete "$EXP/" "$HOST:$RDIR/export_rtl3/"
ssh "$HOST" "cd $RDIR/repo && git pull -q --ff-only && git log -1 --format='%h %s' &&
  . flow/tsmc65/site/sram.sh && export QC_MC_OUT && QC_VCS_OPTS='$VOPTS' \
  QC_BUILD=$RDIR/build QC_SIM_OPTS='+DIR=$RDIR/export_rtl3 +IMG0=$IMG0 +NIMG=$NIMG' QC_PASS_RE='RESULT PASS' \
  QC_FAIL_RE='RESULT FAIL|MISMATCH|Error|Fatal' \
  flow/tsmc65/sim/run_vcs.sh $TAG qa_tb $FL qc18acc/hw3/tb/tb.f" || true
scp -q "$HOST:$RDIR/build/sim/$TAG/sim.log" "$LOC/$LOG.log" || { scp -q "$HOST:$RDIR/build/sim/$TAG/vcs.log" "$LOC/rtl_vcs.log"; grep -E "Error|error" "$LOC/rtl_vcs.log" | head; exit 1; }
grep -E "^(TB|IMAGE|PERF|RESULT|MAP)|MISMATCH|Error" "$LOC/$LOG.log" | head -40
python3 -m qc18acc.hw3.sim.cycles "$LOC/$LOG.log" "$EXP" "$IMG0"
