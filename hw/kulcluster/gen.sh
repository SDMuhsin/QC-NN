#!/usr/bin/env bash
# Regenerate the KUL cluster (public SNAX equivalent) for chimera's TARGET_KULCLUSTER slot.
#   source: github.com/KULeuven-MICAS/snax_cluster @ 3575d72 (6 Dec 2024), config snax_KUL_cluster.hjson
#           with 4 integration tweaks (cfg/snax_KUL_cluster_chimera.hjson, see README.md)
#   output: hw/kulcluster/generated/kulcluster_{sim,vlt,syn}.sv -- single-file morty pickles in which
#           EVERY module/package/interface carries the prefix KULCluster_ (no clash with chimera's
#           own snitch_cluster / axi / common_cells copies). Top: KULCluster_snax_KUL_cluster_wrapper.
# Usage: hw/kulcluster/setup_tools.sh && hw/kulcluster/gen.sh      (~3 min; needs network for sbt/bender)
set -euo pipefail
KUL_NO_VLT=1 source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
SNAX_REPO=https://github.com/KULeuven-MICAS/snax_cluster.git
SNAX_REV=3575d72c066681c876bc31444f09feb6b84d27ca
PREFIX=KULCluster_
OUT=$KUL_DIR/generated
TARGS="-t rtl -t snax_KUL_cluster -t snax_KUL_cluster_xdma -t snax_gemmX"

mkdir -p "$KUL_BUILD" "$OUT"
if [ ! -d "$KUL_SNAX/.git" ]; then
  git clone -q "$SNAX_REPO" "$KUL_SNAX"
fi
git -C "$KUL_SNAX" fetch -q origin "$SNAX_REV" 2>/dev/null || true
git -C "$KUL_SNAX" -c advice.detachedHead=false checkout -q "$SNAX_REV"
git -C "$KUL_SNAX" submodule update -q --init --recursive

# 1) SNAX generation (snaxgen: streamer/CSR-manager/GeMMX/xDMA via Chisel+sbt, wrappers via mako)
cd "$KUL_SNAX/target/snitch_cluster"
cp "$KUL_DIR/cfg/snax_KUL_cluster_chimera.hjson" cfg/snax_KUL_cluster.hjson   # keep upstream name: Makefiles key on it
make rtl-gen CFG_OVERRIDE=cfg/snax_KUL_cluster.hjson > "$KUL_BUILD/rtlgen.log" 2>&1 \
  || { tail -30 "$KUL_BUILD/rtlgen.log"; exit 1; }

# 2) source manifest of the cluster (no testharness) and prefixed pickles
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
pickle sim                       # Questa / VCS simulation
pickle vlt -D VERILATOR -D SYNTHESIS   # Verilator (as upstream snax vlt flow: +define+SYNTHESIS)
pickle syn -D SYNTHESIS          # synthesis
( cd "$KUL_SNAX" && echo "snax_cluster $(git rev-parse HEAD)"; sha256sum "$KUL_DIR/cfg/snax_KUL_cluster_chimera.hjson" ) > "$OUT/VERSION"
ls -la "$OUT"
