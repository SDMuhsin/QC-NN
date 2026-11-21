#!/usr/bin/env bash
# R39 (results/r39.md) fallback preset for the chip top = impl/r36/run36.sh with opt-in env only (no script copied):
#   W ("west channel", QB39_CH um [200]): west strip widened, act kept abutted on column 0, so a CH-wide std-cell
#     channel at x 0..CH joins the gap (south of the act) to the NW band (north of the act).  R14 / R36: u_seq is pulled
#     to two pin clusters on opposite sides of the act -> gpl oscillates / diverges, DPL clumps -> GRT overflow there.
#     QB14_X0 = 900 + CH, QB14_HUBX = 40 + CH (hub column pins at HUBX + 860 + 390 c = X0 + 390 c), die 4030 + CH wide;
#     QB36_PGBB follows the hub.  Final views and latencies as r36_f2.
#   QB39_DENS [0.40], QB39_NB [800].
#   usage (snapshot root on tau4):  qc18bacc/impl/r39/run39.sh <step> <tag> <period>   (steps of run36.sh)
here=$(cd "$(dirname "$0")" && pwd); B=${QC_BUILD:-/tmp/$USER/qc18bacc/build}
CH=${QB39_CH:-200}
export QB14_X0=$(echo "900 + $CH" | bc) QB14_HUBX=$(echo "40 + $CH" | bc)
export QB36_PGBB=${QB36_PGBB:-"$QB14_HUBX 0 $(echo "4030 + $CH" | bc) 1950.8"}
export QB_NB=${QB39_NB:-${QB_NB:-800}} QB_DENS=${QB39_DENS:-${QB_DENS:-0.40}}
export QB11_ABS=${QB11_ABS:-$B/r36/abs4} QB11_INS=${QB11_INS:-1.035} QB14_HINS=${QB14_HINS:-1.669} QB14_AINS=${QB14_AINS:-0.985}
export QB36_TOPL=${QB36_TOPL:-7.7}
export QB_GPL_ARGS=${QB_GPL_ARGS:-"-overflow 0.30 -pad_left 2 -pad_right 2"} QB_DPL_ARGS=${QB_DPL_ARGS:-"-max_displacement {3000 3000}"}
export QB_PC_HOOK=${QB_PC_HOOK-$here/../r36/pc_none.tcl}
echo "R39_PRESET CH $CH X0 $QB14_X0 HUBX $QB14_HUBX PGBB {$QB36_PGBB} NB $QB_NB DENS $QB_DENS ABS $QB11_ABS TOPL $QB36_TOPL"
exec "$here/../r36/run36.sh" "$@"
