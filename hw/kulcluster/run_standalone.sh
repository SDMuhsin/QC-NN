#!/usr/bin/env bash
# Standalone check of the generated KUL cluster on SNAX's own Verilator testbench (unprefixed
# sources in the snax_cluster build tree, same config as the chimera pickles):
# builds bin/snitch_cluster.vlt + SW (LLVM 17), runs snax-gemmx-matmul (+ conv, xdma-memset).
#   hw/kulcluster/run_standalone.sh            (after gen.sh; first HW build ~5 min)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
T=$KUL_SNAX/target/snitch_cluster
CFG=cfg/snax_KUL_cluster.hjson
cd $T
# fesvr: upstream recipe fails on hosts without boost_system; build it without boost
F=work-vlt/riscv-isa-sim
if [ ! -f work-vlt/lib/libfesvr.a ]; then
  make CFG_OVERRIDE=$CFG $F/98d2c29e431f3b14feefbda48c5f70c2f451acf2_unzip
  (cd $F && ./configure --prefix "$PWD" --without-boost --without-boost-asio --without-boost-regex >/dev/null \
     && make -j"$(nproc)" install-config-hdrs install-hdrs libfesvr.a >/dev/null)
  mkdir -p work-vlt/lib && cp $F/libfesvr.a work-vlt/lib/
fi
make CFG_OVERRIDE=$CFG bin/snitch_cluster.vlt -j"$(nproc)" > $KUL_BUILD/vlt.log 2>&1 || { tail -20 $KUL_BUILD/vlt.log; exit 1; }
make CFG_OVERRIDE=$CFG sw LLVM_BINROOT=$QCNN/tools/llvm17/bin -j"$(nproc)" > $KUL_BUILD/sw.log 2>&1 || { tail -20 $KUL_BUILD/sw.log; exit 1; }
rc=0
for app in snax-gemmx-matmul snax-gemmx-conv snax-xdma-memset; do
  d=$KUL_BUILD/run_$app; mkdir -p $d/logs; cd $d
  out=$($T/bin/snitch_cluster.vlt $T/sw/apps/$app/build/$app.elf 2>&1) || rc=1
  echo "$out" | grep -v "^\[fesvr\]\|^\[Tracer\]\|^Warning" | sed "s/^/[$app] /"
  # simulated time of the last retired instruction of core 0 (1 cycle = 1 ns in the TB)
  echo "[$app] end-of-test core0 cycle: $(tail -1 logs/trace_chip_00_hart_00000.dasm | awk '{print $2}')"
done
# same GeMM with phase timing + GeMMX/streamer hardware counters (twin of the chimera test)
A=$T/sw/apps/snax-gemmx-matmul
make -C $A APP=snax-gemmx-matmul-perf SRCS=$KUL_DIR/sw/standalone_gemmx_perf/gemmx_perf.c \
  CFG_OVERRIDE=$CFG LLVM_BINROOT=$QCNN/tools/llvm17/bin >> $KUL_BUILD/sw.log 2>&1 || { tail -20 $KUL_BUILD/sw.log; exit 1; }
d=$KUL_BUILD/run_snax-gemmx-matmul-perf; mkdir -p $d/logs; cd $d
$T/bin/snitch_cluster.vlt $A/build/snax-gemmx-matmul-perf.elf > gemmx_perf.log 2>&1 || rc=1
grep GEMMX_PERF gemmx_perf.log | sed "s/^/[snax-gemmx-matmul-perf] /"
grep -q "GEMMX_PERF err=0 " gemmx_perf.log || rc=1
exit $rc
