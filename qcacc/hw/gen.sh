#!/usr/bin/env bash
# Generate the QC-GeMMX KUL cluster (qcacc/ARCH.md): hw/kulcluster/gen.sh with the qcacc overlay.
#   source: KULeuven-MICAS/snax_cluster @ 3575d72 in its own checkout build/qcacc/snax_cluster
#           (the base tree build/kulcluster/snax_cluster and hw/kulcluster/generated are not touched)
#   overlay: chisel/qcgemm/*.scala      -> hw/chisel_acc/src/main/scala/snax_acc/qcgemm/ (QC core)
#            sv/snax_streamer_gemmX_shell_wrapper.sv -> hw/chisel_acc/src/ (DataWidthB = 64)
#            patches/snax_cluster_qc.patch (snaxgen runs the QC core generator; streamer: per-reader
#              transposer, so the 1 x 64 b B reader has none and the streamer CSR map stays the dense one;
#              snax-gemmx-lib: requant-table CSRs + GEMMX_START/BUSY/PERF moved behind them)
#            cfg/snax_KUL_cluster_qc.hjson (B reader 1 x 64 b, narrow)
#   output:  build/qcacc/generated/kulcluster_{sim,vlt,syn}.sv: same KULCluster_ prefix and top
#            (KULCluster_snax_KUL_cluster_wrapper) as hw/kulcluster, drop-in for chimera.
# Usage: hw/kulcluster/setup_tools.sh && qcacc/hw/gen.sh     (~3 min; network for the first clone)
set -euo pipefail
QHW=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export QCNN=$(cd "$QHW/../.." && pwd)
BASE_SNAX=$QCNN/build/kulcluster/snax_cluster        # only used as a clone reference
export KUL_BUILD=${QC_BUILD:-$QCNN/build/qcacc}
KUL_NO_VLT=1 source "$QCNN/hw/kulcluster/env.sh"     # KUL_SNAX = $KUL_BUILD/snax_cluster
SNAX_REPO=https://github.com/KULeuven-MICAS/snax_cluster.git
SNAX_REV=3575d72c066681c876bc31444f09feb6b84d27ca
PREFIX=KULCluster_
OUT=$KUL_BUILD/generated
TARGS="-t rtl -t snax_KUL_cluster -t snax_KUL_cluster_xdma -t snax_gemmX"

mkdir -p "$KUL_BUILD" "$OUT"
if [ ! -d "$KUL_SNAX/.git" ]; then
  git clone -q --reference-if-able "$BASE_SNAX" --dissociate "$SNAX_REPO" "$KUL_SNAX"
fi
git -C "$KUL_SNAX" fetch -q origin "$SNAX_REV" 2>/dev/null || true
git -C "$KUL_SNAX" checkout -q -- .                         # drop a previous overlay patch (tracked files)
git -C "$KUL_SNAX" -c advice.detachedHead=false checkout -q "$SNAX_REV"
git -C "$KUL_SNAX" submodule update -q --init --recursive

# 0) overlay
git -C "$KUL_SNAX" apply "$QHW/patches/snax_cluster_qc.patch"
rm -rf "$KUL_SNAX/hw/chisel_acc/src/main/scala/snax_acc/qcgemm"
cp -r "$QHW/chisel/qcgemm" "$KUL_SNAX/hw/chisel_acc/src/main/scala/snax_acc/qcgemm"
cp "$QHW/sv/snax_streamer_gemmX_shell_wrapper.sv" "$KUL_SNAX/hw/chisel_acc/src/"

# 1) SNAX generation (as hw/kulcluster/gen.sh)
cd "$KUL_SNAX/target/snitch_cluster"
cp "$QHW/cfg/snax_KUL_cluster_qc.hjson" cfg/snax_KUL_cluster.hjson   # upstream name: Makefiles key on it
make rtl-gen CFG_OVERRIDE=cfg/snax_KUL_cluster.hjson > "$KUL_BUILD/rtlgen.log" 2>&1 \
  || { tail -30 "$KUL_BUILD/rtlgen.log"; exit 1; }
grep -q "module QcBlockGemm" "$KUL_SNAX/hw/chisel_acc/generated/gemmx/BlockGemmRescaleSIMD.sv" \
  || { echo "QC core not generated"; exit 1; }

# 2) source manifest and prefixed pickles (as hw/kulcluster/gen.sh)
cd "$KUL_SNAX"
bender sources -f $TARGS > "$KUL_BUILD/kul_sources.json"
bender script flist $TARGS > "$KUL_BUILD/kul_flist_unprefixed.f"
pickle() { # <name> <morty defines...>
  local n=$1; shift
  morty -f "$KUL_BUILD/kul_sources.json" -p $PREFIX --top snax_KUL_cluster_wrapper "$@" \
        -o "$KUL_BUILD/morty_$n.sv" > "$KUL_BUILD/morty_$n.log" 2>&1 \
    || { tail -30 "$KUL_BUILD/morty_$n.log"; exit 1; }
  python3 "$KUL_DIR/scripts/prefix_fixup.py" "$KUL_BUILD/morty_$n.sv" "$OUT/kulcluster_$n.sv" $PREFIX
}
pickle sim
pickle vlt -D VERILATOR -D SYNTHESIS
pickle syn -D SYNTHESIS
( cd "$KUL_SNAX" && echo "snax_cluster $(git rev-parse HEAD) + qcacc overlay"
  cd "$QHW" && sha256sum cfg/snax_KUL_cluster_qc.hjson patches/snax_cluster_qc.patch \
                         sv/snax_streamer_gemmX_shell_wrapper.sv chisel/qcgemm/*.scala ) > "$OUT/VERSION"
ls -la "$OUT"
