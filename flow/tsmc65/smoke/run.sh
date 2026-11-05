#!/usr/bin/env bash
# Flow smoke test on the server (from the repo root):  flow/tsmc65/smoke/run.sh [period_ns=2.5]
# DC (wire-load and topographical) -> PrimeTime at every site corner -> VCS RTL and zero-delay gate-level simulation.
# Proves the tools start and their licences check out; prints one SMOKE line per step.
set -u
S=$(cd "$(dirname "$0")" && pwd)
F=$S/..
P=${1:-2.5}
B=${QC_BUILD:-$(cd "$F/../.." && pwd)/build/tsmc65}
"$F/syn/run_dc.sh" "$S/rtl.f" mac8 "$P" smoke_mac8
QC_TOPO=1 "$F/syn/run_dc.sh" "$S/rtl.f" mac8 "$P" smoke_mac8_topo
"$F/sta/run_pt.sh" smoke_mac8
"$F/sim/run_vcs.sh" smoke_rtl tb_mac8 "$S/rtl.f" "$S/tb.f"
gls=$B/sim/smoke_gls.f
printf '+incdir+%s\n%s\n%s\n' "$S/include" "$S/mac8_pkg.sv" "$B/syn/smoke_mac8/mac8.v" > "$gls"
QC_GLS=1 "$F/sim/run_vcs.sh" smoke_gls tb_mac8 "$gls" "$S/tb.f"
