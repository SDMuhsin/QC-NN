# Shared helpers, sourced by the sim/*.sh entry points.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"

log() { printf '[sim] %s\n' "$*" >&2; }
die() { printf '[sim] ERROR: %s\n' "$*" >&2; exit 1; }

# Staged snitch_cluster workspace for a config, and its testbench target dir.
ws_dir()  { echo "$SIM_BUILD/ws/$1"; }
tgt_dir() { echo "$SIM_BUILD/ws/$1/target/snitch_cluster"; }
remote_ws() { echo "$REMOTE_WORK/ws/$1"; }

# make in the testbench target dir, with our overlay and the fixed tool paths.
tb_make() {
  local cfg=$1; shift
  make -C "$(tgt_dir "$cfg")" -f Makefile -f "$QCNN_SIM/mk/overlay.mk" \
    CFG_OVERRIDE="cfg/$cfg.hjson" BENDER="$BENDER" LLVM_BINROOT="$LLVM_BINROOT" \
    CLANG_FORMAT="$LLVM_BINROOT/clang-format" DASM="$SPIKE_DASM" "$@"
}

# Run a csh command line on the remote host with Questa in PATH.
remote_questa() {
  ssh "$REMOTE_HOST" "tcsh -c 'source $REMOTE_QUESTA >& /dev/null; setenv PATH $REMOTE_WORK/shims:\$PATH; $*'"
}

require_ws() { [ -d "$(tgt_dir "$1")" ] || die "workspace for '$1' missing; run sim/setup.sh $1"; }
