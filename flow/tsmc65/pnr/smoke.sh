#!/usr/bin/env bash
# P&R smoke test on the server (from the repo root):  flow/tsmc65/pnr/smoke.sh [period_ns=2.5]
# DC synthesis of the smoke MAC (syn/run_dc.sh, tag smoke_mac8) -> OpenROAD P&R -> PrimeTime with the routed SPEF.
set -u
P=$(cd "$(dirname "$0")" && pwd)
F=$P/..
"$F/syn/run_dc.sh" "$F/smoke/rtl.f" mac8 "${1:-2.5}" smoke_mac8
"$P/run_pnr.sh" "$P/designs/smoke_mac8.cfg"
"$P/run_pt_post.sh" smoke_mac8
