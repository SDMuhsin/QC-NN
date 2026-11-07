#!/usr/bin/env bash
# Array-level ablation (M4): dense int8 MAC vs ternary select vs QC butterfly cores, standalone, TSMC 65 nm.
#   qcacc/ablation/run.sh [-H host] [steps...]      default host tau1, default steps: all
# steps: gen (Chisel -> build/qcacc/ablation/rtl), vec (conv1 operand streams + expected D -> build/qcacc/ablation/vec),
#        rtl (Verilator RTL check of the 4 points), push (rsync flow / rtl / vec / scripts to the host work dir),
#        syn (DC 4.2 ns + PT, 3 variants in parallel), fmax (DC at 2.0 ns ss: tags abl_<v>_p2.0), sdf, gls (zd + sdf, 4 points), power (PT PX tt 2.8 ns), fetch, report
# Host work dir: ABL_R (default /tmp/ckp908/qcacc_abl); everything that names kit cells stays there; only the
# summaries of R/out are fetched to build/qcacc/ablation/out, the report goes to qcacc/results/ablation_logs/.
set -euo pipefail
QA=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
QCNN=$(cd "$QA/../.." && pwd)
H=tau1
while getopts "H:" o; do case $o in H) H=$OPTARG;; *) sed -n 2,8p "$0"; exit 2;; esac; done
shift $((OPTIND - 1))
R=${ABL_R:-/tmp/ckp908/qcacc_abl}
B=$QCNN/build/qcacc/ablation
STEPS=${*:-gen vec rtl push syn fmax sdf gls power fetch report}
V="dense ternary qc"; PTS="dense_s2 ternary qc dense_base"
rr() { ssh "$H" "$R/abl/remote.sh $*"; }
par() { local pids=() rc=0; for a in "$@"; do eval "$a" & pids+=($!); done; for p in "${pids[@]}"; do wait "$p" || rc=1; done; return $rc; }
for s in $STEPS; do
  echo "== $s"
  case $s in
  gen) "$QA/gen.sh" ;;
  vec) (cd "$QCNN" && python3 -m qcacc.ablation.vectors "$B/vec") ;;
  rtl)
    (source /workspace/GanAccelAsic/src/flow/env.sh >/dev/null 2>&1
     for v in dense:512 ternary:128 qc:64; do n=${v%:*}
       verilator --binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style +define+DUT=AblGemm_$n +define+BW=${v#*:} \
         --top-module tb_abl -Mdir "$B/vlt/$n" "$B/rtl/AblGemm_$n.sv" "$QA/tb_abl.sv" -o Vtb > "$B/vlt_$n.log" 2>&1
     done
     for p in $PTS; do n=${p%_*}; [ "$p" = ternary ] || [ "$p" = qc ] && n=$p
       "$B/vlt/$n/Vtb" +VEC="$B/vec/$p.txt" | grep ABL_RESULT | sed "s/^/rtl $p /"; done) | tee "$B/rtl.txt"
    ! grep -q FAIL "$B/rtl.txt" ;;
  push)
    ssh "$H" "mkdir -p $R/abl $R/rtl $R/vec $R/flow"
    rsync -a --exclude pnr "$QCNN/flow/tsmc65" "$H:$R/flow/"
    rsync -a "$B/rtl/"*.sv "$H:$R/rtl/"; rsync -a "$B/vec/"*.txt "$H:$R/vec/"
    rsync -a "$QA/remote.sh" "$QA/constraints.sdc" "$QA/pt_hook.tcl" "$QA/pt_power.tcl" "$QA/write_sdf.tcl" \
      "$QA/abl.do" "$QA/tb_abl.sv" "$H:$R/abl/" ;;
  syn)   par "rr syn dense" "rr syn ternary" "rr syn qc" ;;
  fmax)  par "ssh $H ABL_PERIOD_SYN=2.0 ABL_TAG_SFX=_p2.0 $R/abl/remote.sh syn dense" \
             "ssh $H ABL_PERIOD_SYN=2.0 ABL_TAG_SFX=_p2.0 $R/abl/remote.sh syn ternary" \
             "ssh $H ABL_PERIOD_SYN=2.0 ABL_TAG_SFX=_p2.0 $R/abl/remote.sh syn qc" ;;
  sdf)   par "rr sdf dense" "rr sdf ternary" "rr sdf qc" ;;
  gls)   rr cells
         for m in zd sdf; do par "rr gls dense_s2 $m" "rr gls ternary $m" "rr gls qc $m" "rr gls dense_base $m"; done ;;
  power) for m in zd sdf; do par "rr power dense_s2 $m" "rr power ternary $m" "rr power qc $m" "rr power dense_base $m"; done ;;
  fetch) mkdir -p "$B/out"; rsync -a "$H:$R/out/" "$B/out/" ;;
  report) (cd "$QCNN" && python3 -m qcacc.ablation.report "$B" "$QCNN/qcacc/results/ablation_logs") ;;
  *) echo "unknown step $s"; exit 2 ;;
  esac
done
