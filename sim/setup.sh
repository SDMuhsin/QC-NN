#!/usr/bin/env bash
# One-time setup: fetch prebuilt tools into tools/ and stage a snitch_cluster
# workspace for a cluster config under build/sim/ws/<cfg>.
#   sim/setup.sh [cfg]        (default cfg: chimera_fp)
source "$(dirname "$0")/lib/common.sh"
CFG=${1:-$SIM_CFG}
[ -f "$QCNN_SIM/cfg/$CFG.hjson" ] || die "no config sim/cfg/$CFG.hjson"

DL=$QCNN_ROOT/tools/dl
mkdir -p "$DL"

# 1) RISC-V LLVM toolchain (pulp-llvm 0.12.0, as pinned in snitch_cluster/iis-setup.sh)
if [ ! -x "$LLVM_BINROOT/clang" ]; then
  log "fetching pulp-llvm 0.12.0"
  tar=riscv32-pulp-llvm-ubuntu2004-0.12.0.tar.gz
  wget -q -O "$DL/$tar" "https://github.com/pulp-platform/llvm-project/releases/download/0.12.0/$tar"
  mkdir -p "$QCNN_ROOT/tools/riscv-llvm"
  tar xzf "$DL/$tar" --strip-components=1 -C "$QCNN_ROOT/tools/riscv-llvm"
fi

# 2) spike-dasm (trace disassembler, version pinned by the snitch Dockerfile)
if [ ! -x "$SPIKE_DASM" ]; then
  log "fetching snitch spike-dasm 0.1.0"
  tar=snitch-spike-dasm-0.1.0-x86_64-linux-gnu-ubuntu18.04.tar.gz
  wget -q -O "$DL/$tar" "https://github.com/pulp-platform/riscv-isa-sim/releases/download/snitch-v0.1.0/$tar"
  mkdir -p "$(dirname "$SPIKE_DASM")"
  tar xzf "$DL/$tar" -C "$(dirname "$SPIKE_DASM")"
fi

# 3) Python: reggen needs pkg_resources (setuptools < 81)
python -W ignore -c 'import pkg_resources, hjson, mako, jsonref, numpy, torch, pyflexfloat, elftools' \
  || die "tools/venv lacks packages: pip install -r $SNITCH_SRC/python-requirements.txt 'setuptools>=77,<81'"

# 4) Shims: fesvr's configure probes for dtc, which the TB never calls.
mkdir -p "$SIM_BUILD/shims"
cp "$QCNN_SIM/lib/dtc-shim.sh" "$SIM_BUILD/shims/dtc"
cp "$QCNN_SIM/lib/bender-replay.sh" "$SIM_BUILD/shims/bender-replay"
chmod +x "$SIM_BUILD/shims/"*

# 5) Stage the upstream snitch_cluster checkout (never built in place).
WS=$(ws_dir "$CFG")
if [ ! -d "$WS" ]; then
  log "staging $SNITCH_SRC -> $WS"
  mkdir -p "$WS"
  rsync -a "$SNITCH_SRC/" "$WS/"
fi
cp "$QCNN_SIM/cfg/$CFG.hjson" "$(tgt_dir "$CFG")/cfg/$CFG.hjson"
log "setup done for $CFG ($WS)"
