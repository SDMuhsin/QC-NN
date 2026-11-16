#!/usr/bin/env bash
# R8d: PT pre-route of a DC run dir with impl/r8d/pt_xtra.tcl (= R8a classes + b2r and top_glue without the column
# block outputs as separate classes).   qc18bacc/impl/r8d/run_pt.sh <syn tag> [corners]   (on tau, repo root)
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}
t=$1; shift
QC_PT_HOOK=$here/pt_xtra.tcl "$root/flow/tsmc65/sta/run_pt.sh" "$QC_BUILD/syn/$t" "${@:-tt ss}"
