#!/usr/bin/env bash
# Build one kernel, simulate it on the Snitch cluster RTL, self-check it against
# the golden model and record cycle counts.
#   sim/run_kernel.sh <kernel> <vlt|vsim> [cfg]
#   kernel: a file sim/kernels/<kernel>.conf    cfg: sim/cfg/<cfg>.hjson (default chimera_fp)
# Outputs: build/sim/runs/<cfg>/<sim>/<kernel>/ (ELF, logs, traces)
#          sim/results/<kernel>_<sim>_<cfg>.txt (summary)
source "$(dirname "$0")/lib/common.sh"
KERNEL=${1:?usage: run_kernel.sh <kernel> <vlt|vsim> [cfg]}
SIM=${2:?usage: run_kernel.sh <kernel> <vlt|vsim> [cfg]}
CFG=${3:-$SIM_CFG}
CONF=$QCNN_SIM/kernels/$KERNEL.conf
[ -f "$CONF" ] || die "unknown kernel '$KERNEL' (see sim/kernels/*.conf)"
require_ws "$CFG"

APP_DIR= APP= PARAMS= VERIFY= DATAGEN= REGIONS=
source "$CONF"
WS=$(ws_dir "$CFG"); TGT=$(tgt_dir "$CFG")
RUN=$SIM_BUILD/runs/$CFG/$SIM/$KERNEL
rm -rf "$RUN"; mkdir -p "$RUN/build"

# ---- 1) software: runtime + kernel ELF (data from the bundled generator) ----
log "building $KERNEL for $CFG"
export SNITCH_WS=$WS QCNN_SIM
tb_make "$CFG" sw/runtime/rtl > "$RUN/sw_build.log" 2>&1 || die "runtime build failed ($RUN/sw_build.log)"
extra=()
if [ -n "$DATAGEN" ]; then extra+=(DATAGEN_PY="$(eval echo "$DATAGEN")"); fi
make -C "$TGT/$APP_DIR" LLVM_BINROOT="$LLVM_BINROOT" DEBUG=ON \
  DATA_CFG="$QCNN_SIM/kernels/$PARAMS" DATA_H="$RUN/build/data.h" APP_BUILDDIR="$RUN/build" \
  "${extra[@]}" all >> "$RUN/sw_build.log" 2>&1 || die "kernel build failed ($RUN/sw_build.log)"
ELF=$RUN/build/$APP.elf
VERIFY_LOCAL=$(eval echo "$VERIFY")

# ---- 2) simulation + self-check ---------------------------------------------
log "simulating $KERNEL on $SIM"
set +e
case "$SIM" in
  vlt)
    BIN=$TGT/bin/snitch_cluster.vlt
    [ -x "$BIN" ] || die "missing $BIN; run sim/build_hw.sh vlt $CFG"
    (cd "$RUN" && python "$VERIFY_LOCAL" "$BIN" "$ELF" --log sim.log --dump-results) > "$RUN/verify.log" 2>&1
    RC=$?
    ;;
  vsim)
    RWS=$(remote_ws "$CFG")
    RRUN=$REMOTE_WORK/runs/$CFG/$KERNEL
    rverify=${VERIFY_LOCAL/#$WS/$RWS}; rverify=${rverify/#$QCNN_SIM/$REMOTE_WORK/qcnn_sim}
    ssh "$REMOTE_HOST" "rm -rf $RRUN && mkdir -p $RRUN"
    rsync -a --exclude results/ "$QCNN_SIM/" "$REMOTE_HOST:$REMOTE_WORK/qcnn_sim/"
    rsync -a "$RUN/build" "$REMOTE_HOST:$RRUN/"
    remote_questa "setenv SNITCH_WS $RWS; cd $RRUN && $REMOTE_WORK/venv/bin/python $rverify \
      $RWS/target/snitch_cluster/bin/snitch_cluster.vsim $RRUN/build/$APP.elf --log sim.log --dump-results" \
      > "$RUN/verify.log" 2>&1
    RC=$?
    rsync -a "$REMOTE_HOST:$RRUN/logs" "$REMOTE_HOST:$RRUN/sim.log" "$REMOTE_HOST:$RRUN/results.csv" "$RUN/" 2>/dev/null
    ;;
  *) die "unknown simulator '$SIM' (vlt|vsim)";;
esac
set -e

# ---- 3) traces -> per-region performance, summary ---------------------------
for d in "$RUN"/logs/trace_hart_*.dasm; do
  [ -e "$d" ] || continue
  h=$(basename "$d" .dasm); h=${h#trace_hart_}
  "$SPIKE_DASM" < "$d" | python "$WS/util/trace/gen_trace.py" --permissive \
    -d "$RUN/logs/hart_${h}_perf.json" > "$RUN/logs/trace_hart_$h.txt"
done
mkdir -p "$QCNN_SIM/results"
OUT=$QCNN_SIM/results/${KERNEL}_${SIM}_${CFG}.txt
python "$QCNN_SIM/lib/summarize.py" --kernel "$KERNEL" --sim "$SIM" --cfg "$CFG" \
  --params "$QCNN_SIM/kernels/$PARAMS" --run "$RUN" --rc "$RC" --regions "$REGIONS" > "$OUT"
cat "$OUT"
exit "$RC"
