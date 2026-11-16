#!/usr/bin/env bash
# R8a: PT pre-route of a DC run dir with the R8a hook (pt_class.tcl + pt_xtra.tcl classes / endpoint lists).
#   qc18bacc/impl/r8a/run_pt.sh <syn tag> [corners]     (on tau, repo root; QC_BUILD as impl/r4)
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}
t=$1; shift
QC_PT_HOOK=$here/pt_xtra.tcl "$root/flow/tsmc65/sta/run_pt.sh" "$QC_BUILD/syn/$t" "${@:-tt ss}"
