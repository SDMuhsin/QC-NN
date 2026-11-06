#!/usr/bin/env bash
# Build the chimera ELF that runs ResNet-8 on the KUL cluster:
#   nn/sw/build.sh [-DNN_FULL_CHECK] [-DNN_NO_DMA]  -> $NN_BUILD/resnet8.memisl.elf (+ .dump)
# Needs build/gen/nn_net.c (python -m nn.compile.main) and the GeMMX CSR headers/lib of the
# generated snax_cluster tree (hw/kulcluster/gen.sh).  Same toolchain and flags as
# hw/kulcluster/sw/chimera_gemmx/build.sh (upstream clang 17, rv32im, chimera memisl.ld).
set -euo pipefail
NN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUL_NO_VLT=1 source "$NN/../hw/kulcluster/env.sh"
CHIM=${CHIM:-$QCNN/third_party/chimera}
CHS=$(cd "$CHIM" && bender path cheshire)
SNSW=$KUL_SNAX/target/snitch_cluster/sw
GEN=${NN_GEN:-$NN/build/gen}
O=${NN_BUILD:-$NN/build/sw}; mkdir -p "$O"
[ -f "$GEN/nn_net.c" ] || { echo "missing $GEN/nn_net.c: run python -m nn.compile.main"; exit 1; }
CC=$QCNN/tools/llvm17/bin/clang
CFLAGS="--target=riscv32-unknown-elf -march=rv32im -mabi=ilp32 -mcmodel=medany -mno-relax -O2 \
  -ffreestanding -fno-builtin -fno-common -ffunction-sections -fdata-sections -Wall -Wno-unused-function \
  -DKUL_HART0=7 $* -I$NN/sw -I$GEN -I$KUL_DIR/sw/chimera_gemmx/shim -I$KUL_DIR/sw/chimera_gemmx \
  -I$CHIM/sw/include -I$CHS/sw/include -I$SNSW/snax/gemmx/include -I$KUL_SNAX/sw/snRuntime/src"
set -x
$CC $CFLAGS -c "$CHS/sw/lib/32/crt0.S" -o "$O/crt0.o"
$CC $CFLAGS -c "$CHIM/sw/lib/offload.c" -o "$O/offload.o"
$CC $CFLAGS -c "$SNSW/snax/gemmx/src/snax-gemmx-lib.c" -o "$O/snax-gemmx-lib.o"
$CC $CFLAGS -c "$NN/sw/nn_entry.S" -o "$O/nn_entry.o"
$CC $CFLAGS -c "$NN/sw/nn_cluster.c" -o "$O/nn_cluster.o"
$CC $CFLAGS -c "$NN/sw/nn_host.c" -o "$O/nn_host.o"
$CC $CFLAGS -c "$GEN/nn_net.c" -o "$O/nn_net.o"
$CC $CFLAGS -c "$GEN/nn_full.c" -o "$O/nn_full.o"
$CC $CFLAGS -nostdlib -fuse-ld=lld -Wl,--gc-sections -L"$CHIM/sw/link" -T"$NN/sw/nn_memisl.ld" \
  -o "$O/resnet8.memisl.elf" "$O"/{crt0,nn_host,offload,nn_entry,nn_cluster,nn_net,nn_full,snax-gemmx-lib}.o
$QCNN/tools/llvm17/bin/llvm-objdump -d -h "$O/resnet8.memisl.elf" > "$O/resnet8.memisl.dump"
set +x
$QCNN/tools/llvm17/bin/llvm-size "$O/resnet8.memisl.elf"
