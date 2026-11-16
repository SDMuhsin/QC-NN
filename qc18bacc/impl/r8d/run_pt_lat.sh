#!/usr/bin/env bash
# R8d: PT pre-route of DC run <tag> with the column clk pins at -L latency (impl/r8d/pt_lat.tcl) in <tag>_lat (links).
#   qc18bacc/impl/r8d/run_pt_lat.sh <syn tag> [corners]     (on tau, repo root; QC_BUILD as impl/r4)
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../../.." && pwd)
export QC_BUILD=${QC_BUILD:-/tmp/$USER/qc18bacc/build}
t=$1; shift; s=$QC_BUILD/syn/$t; d=$QC_BUILD/syn/${t}_lat
mkdir -p "$d/rpt"; for f in "$s"/*.v "$s"/*.spef "$s"/*.sdc "$s"/run.env "$s"/*.ddc; do [ -e "$f" ] && ln -sf "$f" "$d/"; done
QC_PT_HOOK=$here/pt_lat.tcl "$root/flow/tsmc65/sta/run_pt.sh" "$d" "${@:-tt ss}"
