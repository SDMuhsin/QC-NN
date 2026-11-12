# qc18bacc microblocks: area / timing (TSMC65 tcbn65gplus, DC wire-load mode)

Flow: `qc18bacc/impl/run.sh all <top> 2.0`. This calls flow/tsmc65 `run_dc.sh` and `run_pt.sh`, the same flow as qc18acc: DC W-2024.09-SP2 `compile_ultra -no_autoungroup -gate_clock`, WLM WireAreaLowkCon/enclosed, 0.25 ns setup uncertainty, IO delay 20 %, PT pre-CTS ideal clocks.
Period 2.0 ns. The main compile corner is **tt** (`QC_CORNER=tt`), which gives the 500 MHz tt target. The ss-compile rows (qc18acc default: compile at ss) show what closing 500 MHz at ss would cost.
fmax = 1/(P - WNS) from PT. DC recovers area until each path just meets 2.0 ns, so a tt fmax of about 501 means "meets 500 MHz at tt". It is not a design limit.
Area/MAC = PE area / (KB*16) (2 terms x 8 lanes per block).
PE split: in = S0 input registers, pop = rotate/xor/popcount + u/nneg registers, acc = sum/shift/add-sub + 8 x ACC_W acc + 8 x ACC_W shadow (+ICG); rest = control pipeline (about 200 um2).

| block (compile) | area um2 | area/MAC | in / pop / acc (comb+seq) | regs | fmax tt / ss MHz | depth |
|---|---|---|---|---|---|---|
| qb_pe KB8 A20 (tt)  | 9995  | 78.1 | 1183 / 2771 / 5841 (3587+2254)   | 565  | 501 / 321 | 3 |
| qb_pe KB16 A20 (tt) | 13910 | 54.3 | 2168 / 5456 / 6089 (3835+2254)   | 718  | 501 / 319 | 3 |
| qb_pe KB32 A20 (tt) | 21494 | 42.0 | 4138 / 10848 / 6310 (4056+2254)  | 1015 | 501 / 319 | 3 |
| qb_pe KB16 A14 (tt) | 12332 | 48.2 | 2127 / 5455 / 4593 (3009+1584)   | 610  | 514 / 331 | 3 |
| qb_lane_n (tt)      | 7214  | -    | -                                | 259  | 501 / 316 | 4 |
| qb_lane_w (tt)      | 9061  | -    | -                                | 287  | 501 / 314 | 4 |
| qb_pe KB8 A20 (ss)  | 11160 | 87.2 | 1192 / 3017 / 6752  | 565  | 745 / 501 | 3 |
| qb_pe KB16 A20 (ss) | 15452 | 60.4 | 2196 / 5894 / 7163  | 718  | 746 / 501 | 3 |
| qb_pe KB32 A20 (ss) | 24207 | 47.3 | 4256 / 12622 / 7129 | 1015 | 753 / 501 | 3 |
| qb_pe KB16 A14 (ss) | 13556 | 53.0 | 2151 / 5903 / 5344  | 610  | 745 / 501 | 3 |
| qb_lane_n (ss)      | 7564  | -    | -                   | 259  | 747 / 501 | 4 |
| qb_lane_w (ss)      | 10026 | -    | -                   | 287  | 745 / 501 | 4 |

Depth (register stages from input to state/output):
- PE: S0 input registers, S1 popcount registers, then the acc/shadow update at S2. An input of cycle n reaches acc at edge n+2.
- Lane: S0 inputs, S1 product (plus h+r and the x>=T compare), S2 round-shift and 18-b clamp, S3 add h+r, saturate, compare. Latency 4.

Critical path (tt compile): nneg_q -> u - nneg -> << plane -> +/- -> acc MSB (PE). The lane is balanced, with every stage close to the limit.

Self-check (`qc18bacc/hw/tb/run_tb.sh`, Verilator 5.050, `gen.py` Python reference written from the arithmetic definitions, 200,000 random cycles each, seed 7; raw lines in micro_tb.txt): **PASS, 0 errors** for all 4 PE configurations and both lanes.
The bench's sensitivity was checked with RTL mutants: wrong -1 detection gives 9427 errors, and a wrong rotate direction gives 14318.
Raw per-run numbers: micro_runs.txt.
