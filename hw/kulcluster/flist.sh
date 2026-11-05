#!/usr/bin/env bash
# File list of chimera with the KUL cluster in the TARGET_KULCLUSTER slot.
#   hw/kulcluster/flist.sh [synth|sim|vlt|kul-only]   (default synth) > chimera_kul.f
# synth   : chimera RTL (-t rtl -t synthesis), KUL cluster = generated/kulcluster_syn.sv
# sim     : + testbench targets (-t test -t sim), KUL cluster = generated/kulcluster_sim.sv
# vlt     : bender script verilator (KUL cluster = generated/kulcluster_vlt.sv)
# kul-only: just the self-contained KUL cluster pickle for synthesis
#           (top KULCluster_snax_KUL_cluster_wrapper; all units prefixed KULCluster_)
# Note: the KUL TCDM / I-cache use the generic KULCluster_tc_sram (behavioural); a synthesis flow
# must map KULCluster_tc_sram{,_impl} to macros just like chimera's own tc_sram.
set -euo pipefail
KUL_NO_VLT=1 source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
CHIM=${CHIM:-$QCNN/third_party/chimera}
BASE="-t snitch_cluster -t cv32a6_convolve -t cva6 -t rtl -t kulcluster"
cd $CHIM
case "${1:-synth}" in
  synth)    bender script flist-plus $BASE -t synthesis ;;
  sim)      bender script flist-plus $BASE -t test -t sim ;;
  vlt)      bender script verilator $BASE ;;
  kul-only) echo "$KUL_DIR/generated/kulcluster_syn.sv" ;;
  *) echo "usage: $0 [synth|sim|vlt|kul-only]" >&2; exit 1 ;;
esac
