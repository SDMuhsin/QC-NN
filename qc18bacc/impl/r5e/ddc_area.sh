#!/usr/bin/env bash
# R5e: impl/r5e/ddc_area.tcl on a DC run dir (run on tau): qc18bacc/impl/r5e/ddc_area.sh <syn run dir> <top>
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../flow/tsmc65/common/tool.sh"
set -a; . "$1/run.env"; set +a
export QC_OUT=$1 QC_TOP=$2 QC_CORNER=${QC_CORNER:-tt}
qc_tool "$1/ddc_area.log" dc_shell -f "$HERE/ddc_area.tcl"
grep R5E_DDC_AREA "$1/ddc_area.log"
