#!/usr/bin/env bash
# Build and run the cluster program natively (x86 -m32, no libc) on a GeMMX C model:
# checks the generated tables, TCDM plan, core kernels and checksums before any RTL run.
set -euo pipefail
NN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
QCNN=$(cd "$NN/.." && pwd)
SNAX=${KUL_SNAX:-$QCNN/build/kulcluster/snax_cluster}
GEN=${NN_GEN:-$NN/build/gen}
O=${NN_NATIVE_BUILD:-$NN/build/native}; mkdir -p "$O"   # NN_NATIVE_C: GeMMX model source (default native.c)
gcc -m32 -O2 -ffreestanding -nostdlib -static -fno-pic -no-pie -fno-builtin -Wall -Wno-unused-function -Wno-unknown-pragmas \
  -DNN_NATIVE -DKUL_HART0=7 "$@" -I"$NN/sw" -I"$NN/sw/native/shim" -I"$GEN" -I"$QCNN/hw/kulcluster/sw/chimera_gemmx" \
  -I"$SNAX/target/snitch_cluster/sw/snax/gemmx/include" \
  -I"$SNAX/sw/snRuntime/src" \
  "${NN_NATIVE_C:-$NN/sw/native/native.c}" "$NN/sw/nn_cluster.c" "$GEN/nn_net.c" "$GEN/nn_full.c" -o "$O/nn_native"
"$O/nn_native"
