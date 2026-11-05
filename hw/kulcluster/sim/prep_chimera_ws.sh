#!/usr/bin/env bash
# Stage a private copy of third_party/chimera (incl. its bender checkouts) in $KUL_BUILD/chimera_ws
# and run chimera's hardware/sim init there, so the shared checkout used by other flows stays
# untouched. Equivalent to upstream `make chs-hw-init chim-sim` minus the SW build (needs GCC):
#   update_plic (36 src/targets), chs-hw-all (CLINT 18 harts, regs), gen_idma_hw, flash/eeprom models.
# The Infineon HyperRAM model is no longer downloadable -> stub (sim/models/s27ks0641_stub.v).
set -euo pipefail
KUL_NO_VLT=1 source "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
WS=$KUL_BUILD/chimera_ws
mkdir -p $WS
rsync -a --exclude '/.git' $QCNN/third_party/chimera/ $WS/
cp $QCNN/third_party/.bender.yml $KUL_BUILD/.bender.yml     # same overrides (paths are absolute)
cd $WS
bender checkout
make update_plic
mkdir -p "$(bender path cheshire)/.bender"
make -B chs-hw-all CHS_XLEN=32 > $WS/chs_hw.log 2>&1 || { tail -20 $WS/chs_hw.log; exit 1; }
make gen_idma_hw > $WS/idma.log 2>&1 || { tail -20 $WS/idma.log; exit 1; }
M=$(bender path cheshire)/target/sim/models; mkdir -p $M
[ -s $M/s25fs512s.v ] || wget -q --no-check-certificate https://freemodelfoundry.com/fmf_vlog_models/flash/s25fs512s.v -O $M/s25fs512s.v
if [ ! -s $M/24FC1025.v ]; then
  wget -q https://ww1.microchip.com/downloads/en/DeviceDoc/24xx1025_Verilog_Model.zip -O $M/m.zip
  unzip -p $M/m.zip 24FC1025.v > $M/24FC1025.v; rm -f $M/m.zip; fi
mkdir -p target/sim/models/s27ks0641
cp $KUL_DIR/sim/models/s27ks0641_stub.v target/sim/models/s27ks0641/s27ks0641.v
: > target/sim/models/s27ks0641/s27ks0641.sdf
echo "chimera workspace ready: $WS"
