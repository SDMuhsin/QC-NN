# Source me (bash): environment for the Snitch-cluster RTL simulation flow.
#   source sim/env.sh
# Every value can be overridden by exporting it before sourcing.

QCNN_SIM=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
QCNN_ROOT=$(cd "$QCNN_SIM/.." && pwd)
export QCNN_SIM QCNN_ROOT

# Upstream snitch_cluster checkout (resolved by bender as a chimera dependency).
export SNITCH_SRC=${SNITCH_SRC:-$QCNN_ROOT/third_party/chimera/.bender/git/checkouts/snitch_cluster-6e8cfa984d0d0605}
# Git-ignored build area: one staged copy of snitch_cluster per cluster config.
export SIM_BUILD=${SIM_BUILD:-$QCNN_ROOT/build/sim}
export SIM_CFG=${SIM_CFG:-chimera_fp}

# Toolchain: pulp-platform/llvm-project 0.12.0 (pinned by snitch_cluster iis-setup.sh).
export LLVM_BINROOT=${LLVM_BINROOT:-$QCNN_ROOT/tools/riscv-llvm/bin}
export SPIKE_DASM=${SPIKE_DASM:-$QCNN_ROOT/tools/spike-dasm/spike-dasm}
export BENDER=${BENDER:-$QCNN_ROOT/tools/bender/bin/bender}
export PATH=$SIM_BUILD/shims:$QCNN_ROOT/tools/venv/bin:$(dirname "$BENDER"):$PATH

# Verilator 5.044 from the (read-only) GanAccelAsic devshell; only the binary
# path is taken, the devshell itself is not kept in this environment.
if [ -z "${VERILATOR:-}" ]; then
  VERILATOR=$(bash -c 'source /workspace/GanAccelAsic/src/flow/env.sh >/dev/null 2>&1; \
                       readlink -f "$(command -v verilator)"' 2>/dev/null)
fi
export VERILATOR
[ -n "$VERILATOR" ] && export VERILATOR_ROOT=$(dirname "$VERILATOR")/../share/verilator

# Remote Questa host. Home on tau is over quota, so the work area lives in /tmp
# on the host (local disk, not shared between tau hosts).
export REMOTE_HOST=${REMOTE_HOST:-tau1}
export REMOTE_WORK=${REMOTE_WORK:-/tmp/ckp908/qcnn_work_sim}
export REMOTE_QUESTA=${REMOTE_QUESTA:-/CMC/scripts/siemens.questasim.2022.1_2.csh}
