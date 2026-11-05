# Source me (bash): tool paths for the KUL cluster (SNAX) generator and standalone sim.
# Tools are installed into $QCNN/tools by hw/kulcluster/setup_tools.sh.
QCNN=${QCNN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
export QCNN
export KUL_DIR=$QCNN/hw/kulcluster
export KUL_BUILD=${KUL_BUILD:-$QCNN/build/kulcluster}
export KUL_SNAX=$KUL_BUILD/snax_cluster
export JAVA_HOME=$QCNN/tools/jdk
# Verilator 5.044 (+ gcc) from the read-only GanAccelAsic LibreLane devshell; only needed for the standalone sim.
if [ -z "${KUL_NO_VLT:-}" ] && ! command -v verilator >/dev/null 2>&1; then
  source /workspace/GanAccelAsic/src/flow/env.sh
fi
if command -v verilator >/dev/null 2>&1; then
  export VERILATOR_ROOT=$(dirname "$(dirname "$(readlink -f "$(command -v verilator)")")")/share/verilator
fi
export PATH=$QCNN/tools/snax-venv/bin:$JAVA_HOME/bin:$QCNN/tools/sbt/bin:$QCNN/tools/bender/bin:$QCNN/tools/morty/bin:$PATH
# upstream LLVM 17 (generic toolchain used by snax CI) + clang-format; dtc shim for fesvr's configure
export PATH=$PATH:$QCNN/tools/llvm17/bin:$QCNN/tools/stubbin
