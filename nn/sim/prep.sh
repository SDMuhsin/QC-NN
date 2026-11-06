#!/usr/bin/env bash
# Local preparation of a ResNet-8 simulation run (shared by nn/sim/run_rtl.sh and nn/gls/run_gls.sh):
#   nn/sim/prep.sh <dir> <first> <images> [build flags]
# compiles the network for test images first..first+images-1 (nn.compile.main), builds the chimera ELF
# (nn/sw/build.sh) and writes the run directory <dir>/run: banks/ (memory-island image), stub.elf (8 B
# JTAG stub), the Tcl of the memory-island backdoor and marker.txt (where nn_result.marker sits).
set -euo pipefail
NN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QCNN=$(cd "$NN/.." && pwd)
L=$1; FIRST=$2; IMAGES=$3; shift 3
FLAGS="$*"
mkdir -p "$L"
echo "--first $FIRST --images $IMAGES $FLAGS" > "$L/cmd.txt"
(cd "$QCNN" && python3 -m nn.compile.main --images "$IMAGES" --first "$FIRST" --check "$IMAGES" --out "$L/gen") > "$L/compile.txt"
NN_GEN=$L/gen NN_BUILD=$L/sw "$NN/sw/build.sh" $FLAGS > "$L/build.txt" 2>&1
python3 "$NN/sim/memisl.py" banks "$L/sw/resnet8.memisl.elf" "$L/run/banks"
mv "$L/run/banks/stub.elf" "$L/run/"
python3 "$NN/sim/memisl.py" where "$L/sw/resnet8.memisl.elf" nn_result > "$L/run/marker.txt"
cp "$NN/sim/memisl.tcl" "$L/run/"
