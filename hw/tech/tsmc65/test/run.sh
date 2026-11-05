#!/usr/bin/env bash
# tc_sram overlay test in VCS with the vendor macro models, on the server (macro views of this host):
#   hw/tech/tsmc65/test/run.sh        -> $QC_BUILD/sim/tc_sram/, last line SIM_DONE tc_sram PASS|FAIL
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
. "$ROOT/flow/tsmc65/site/sram.sh"
export QC_MC_OUT QC_BUILD=${QC_BUILD:-/tmp/$USER/qcnn/build}
QC_PASS_RE='PASS tb_tc_sram' QC_FAIL_RE='FAIL|Fatal' "$ROOT/flow/tsmc65/sim/run_vcs.sh" tc_sram tb_tc_sram "$HERE/tb.f"
