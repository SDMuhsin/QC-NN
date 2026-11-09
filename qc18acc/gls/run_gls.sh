#!/usr/bin/env bash
# QC18-ACC zero-delay gate-level simulation of the full network (VCS) on the DC netlist of qc18acc/impl/run.sh, run
# from the local repo (like hw/sim/run_rtl.sh, whose export it reuses):
#   qc18acc/gls/run_gls.sh start [host=usask] [syn_tag=qa_w3.5] [first_image=0] [n_images=1]
#   qc18acc/gls/run_gls.sh check [host=usask] [syn_tag=qa_w3.5]       (status, or result when finished)
# start: rsync $QC_LOCAL/export_rtl (hw/sim/run_rtl.sh export, with names.txt) to <host>, git pull the host-local
#   clone, generate the TB backdoor include (gen_snap.py) from $QC_RDIR/build/syn/<tag>/qa_top.v, then in the
#   background flow/tsmc65/sim/run_vcs.sh with QC_GLS=1 (tcbn65gplus cell models, +nospecify +notimingcheck), the
#   macro Verilog models (hw/tech/macros_sim.f), qa_tb +define+QA_GLS+QA_SAIF: maps (backdoor) and logits (host port)
#   checked per image like the RTL run, SAIF of the whole DUT over START..DONE of the first image.
# check: fetch sim.log to $QC_LOCAL/gls_<tag>.log, print the result, compare the per-image / per-pass cycles with the
#   RTL log ($QC_LOCAL/rtl_sim.log).  Remote: $QC_RDIR/build/sim/gls_<tag>/ (sim.log, vcs.log),
#   SAIF $QC_RDIR/gls/<tag>/qa_top_img<first>.saif (stays on the host).
# Environment: QC_RDIR (default /tmp/ckp908/qc18acc), QC_LOCAL (default /tmp/root/qc18acc).
set -eu
CMD=${1:?start|check}; HOST=${2:-usask}; T=${3:-qa_w3.5}; IMG0=${4:-0}; NIMG=${5:-1}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
RDIR=${QC_RDIR:-/tmp/ckp908/qc18acc}
LOC=${QC_LOCAL:-/tmp/root/qc18acc}
EXP=$LOC/export_rtl
G=$RDIR/gls/$T
case "$CMD" in
start)
    [ -f "$EXP/names.txt" ] || { echo "no $EXP/names.txt: run qc18acc/hw/sim/run_rtl.sh first"; exit 1; }
    ssh "$HOST" "mkdir -p $RDIR/export_rtl $G"
    rsync -a --delete "$EXP/" "$HOST:$RDIR/export_rtl/"
    ssh "$HOST" "set -e; cd $RDIR/repo && git pull -q --ff-only && git log -1 --format='%h %s'
      N=$RDIR/build/syn/$T/qa_top.v; test -f \$N || { echo no netlist \$N; exit 1; }
      python3 -I qc18acc/gls/gen_snap.py \$N > $G/qa_gls_snap.svh; head -1 $G/qa_gls_snap.svh
      . flow/tsmc65/site/sram.sh; export QC_MC_OUT QA_NETLIST=\$N QC_BUILD=$RDIR/build QC_GLS=1
      export QC_VCS_OPTS='+define+QA_GLS+QA_SAIF +incdir+$G' QC_PASS_RE='RESULT PASS' QC_FAIL_RE='RESULT FAIL|MISMATCH|Error|Fatal'
      export QC_SIM_OPTS='+DIR=$RDIR/export_rtl +IMG0=$IMG0 +NIMG=$NIMG +SAIF=$G/qa_top_img$IMG0.saif'
      nohup flow/tsmc65/sim/run_vcs.sh gls_$T qa_tb qc18acc/gls/gls.f qc18acc/hw/tech/macros_sim.f qc18acc/hw/tb/tb.f > $G/run.log 2>&1 < /dev/null &
      echo GLS started on \$(hostname -s): $RDIR/build/sim/gls_$T" ;;
check)
    S=$RDIR/build/sim/gls_$T
    if ssh "$HOST" "pgrep -f 'run_vcs.sh gls_$T' > /dev/null"; then
        ssh "$HOST" "echo running; tail -c 300 $S/sim.log 2>/dev/null || tail -3 $S/vcs.log"; exit 0
    fi
    ssh "$HOST" "cat $G/run.log; ls -la $G/*.saif 2>/dev/null" || true
    scp -q "$HOST:$S/sim.log" "$LOC/gls_$T.log" || { ssh "$HOST" "grep -E 'Error' -A3 $S/vcs.log | head -20"; exit 1; }
    grep -E "^(TB|IMAGE|PERF|RESULT|MAP|SAIF)|MISMATCH|Error" "$LOC/gls_$T.log" | head -40
    python3 - "$LOC/gls_$T.log" "$LOC/rtl_sim.log" <<'PY'
import re, sys
def cyc(p):
    return {(m[1], m[2]): m[3] for m in re.findall(r"^PASSCYC img (\d+) pass (\d+) \S+ (\d+)", open(p).read(), re.M)} | \
           {(m[1], "total"): m[2] for m in re.findall(r"^PERF img (\d+) total (\d+)", open(p).read(), re.M)}
g, r = cyc(sys.argv[1]), cyc(sys.argv[2])
diff = [k for k in g if k in r and g[k] != r[k]]
imgs = sorted({k[0] for k in g})
print(f"CYCLES gate-level vs RTL: images {','.join(imgs)}, {len(g)} counters compared, {len(diff)} differ"
      + "".join(f"; img {k[0]} {k[1]}: {g[k]} vs {r[k]}" for k in diff[:5])
      + "".join(f"; img {i} total {g[(i, 'total')]}" for i in imgs if (i, 'total') in g))
PY
    ;;
*) sed -n 2,14p "$0"; exit 1 ;;
esac
