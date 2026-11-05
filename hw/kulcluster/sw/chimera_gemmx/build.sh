#!/usr/bin/env bash
# Build the chimera host ELF that offloads the SNAX GeMM test to the KUL cluster.
#   hw/kulcluster/sw/chimera_gemmx/build.sh  -> $KUL_BUILD/sw/chimera_gemmx.memisl.elf
# Toolchain: upstream clang/lld 17 (tools/llvm17), rv32im/ilp32 for both CVA6 (host) and the
# Snitch cores, as chimera does (sw.mk: -march=rv32im). Requires hw/kulcluster/gen.sh to have run
# (uses the generated GeMMX CSR map + datagen output in the snax_cluster build tree).
set -euo pipefail
KUL_NO_VLT=1 source "$(dirname "${BASH_SOURCE[0]}")/../../env.sh"
HERE=$KUL_DIR/sw/chimera_gemmx
CHIM=${CHIM:-$QCNN/third_party/chimera}
CHS=$(cd $CHIM && bender path cheshire)
SNSW=$KUL_SNAX/target/snitch_cluster/sw
APP=$SNSW/apps/snax-gemmx-matmul
O=$KUL_BUILD/sw; mkdir -p $O
# golden data from snax's datagen (same params.hjson as the standalone test)
[ -f $APP/data/data.h ] || make -C $APP/data -f Makefile DATA_DIR=. 2>/dev/null || true
[ -f $APP/data/data.h ] || { echo "missing $APP/data/data.h: run the standalone flow (run_standalone.sh) first"; exit 1; }
CC=$QCNN/tools/llvm17/bin/clang
CFLAGS="--target=riscv32-unknown-elf -march=rv32im -mabi=ilp32 -mcmodel=medany -mno-relax -O2 \
  -ffreestanding -fno-builtin -fno-common -ffunction-sections -fdata-sections -Wall -Wno-unused-function \
  -I$HERE/shim -I$HERE -I$CHIM/sw/include -I$CHS/sw/include \
  -I$SNSW/snax/gemmx/include -I$KUL_SNAX/sw/snRuntime/src -I$APP/data"
set -x
$CC $CFLAGS -c $CHS/sw/lib/32/crt0.S -o $O/crt0.o
$CC $CFLAGS -c $CHIM/sw/lib/offload.c -o $O/offload.o
$CC $CFLAGS -c $SNSW/snax/gemmx/src/snax-gemmx-lib.c -o $O/snax-gemmx-lib.o
$CC $CFLAGS -c $HERE/kul_entry.S -o $O/kul_entry.o
$CC $CFLAGS -c $HERE/kul_gemm.c -o $O/kul_gemm.o
$CC $CFLAGS -c $HERE/main.c -o $O/main.o
$CC $CFLAGS -nostdlib -fuse-ld=lld -Wl,--gc-sections -L$CHIM/sw/link -T$CHIM/sw/link/memisl.ld \
  -o $O/chimera_gemmx.memisl.elf $O/crt0.o $O/main.o $O/offload.o $O/kul_entry.o $O/kul_gemm.o $O/snax-gemmx-lib.o
$QCNN/tools/llvm17/bin/llvm-objdump -d -h $O/chimera_gemmx.memisl.elf > $O/chimera_gemmx.memisl.dump
set +x
$QCNN/tools/llvm17/bin/llvm-size $O/chimera_gemmx.memisl.elf
