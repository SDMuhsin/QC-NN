# Array-level ablation (M4): dense int8 MAC vs plain ternary vs QC butterfly

Question: how much of the QC array's gain comes from removing the multipliers (plain ternary weights), and how much
from the QC butterfly structure?

We compare three standalone 8x8x8 GeMM cores (`qcacc/hw/chisel/ablation/AblGemm.scala`, `AblBlockGemm`). All three
have the same `BlockGemm` control, input cut, int32 accumulators, add-C, and A (512 b) / C / D interfaces. Only the
array and the B width differ:

| core | tile datapath | B per fire |
|---|---|---|
| dense | upstream `GemmArray` / `Mesh` / `Tile`: 8 x (9x9 multiplier), per-tile subtraction | 512 b (int8) |
| ternary | `TernaryGemmArray`: x_k = a_k - sub_a shared per row, 8 x {0, +x, -x} + 7 adders, no butterfly | 128 b (2-bit trits) |
| QC | existing `QcGemmArray`: row butterfly (x, s, d), column decoder, 4-term select + 3 adders | 64 b (code word) |

Flow: `qcacc/ablation/run.sh` (tau1, `/tmp/ckp908/qcacc_abl`). It uses the same `flow/tsmc65` tree as `qc_w4.2` and
`kul_w4.2p` (verified identical): DC 2024.09, WireAreaLowkCon enclosed, 4.2 ns at ss, the cluster's uncertainty and
IO rules (`constraints.sdc`, IO delay 20 %).

Operand stream: the real conv1 GeMMX call of image 0 (K 18, N 2, M 128; 4608 fires = 2.36 M dense-equivalent MACs).
* s2 (qc-mode schedule model): A and C are identical for the three s2 points. B is encoded per core: int8 ternary
  for dense, trits for ternary, code words for QC.
* dense baseline ResNet-8: its own conv1 A / B / C on the dense core.

Every point runs at full rate (no stalls): 4866 busy cycles in all cases.

## Area and fmax (pre-CTS, ideal clock, WLM)

| core | DC 4.2 ns ss: area um2 (kGE) | vs dense | array um2 | per tile | butterflies + decoder (ternary: row x) | fmax tt, PT (all paths / reg2reg) | DC 2.0 ns ss: area um2 | fmax ss / tt at 2.0 ns |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| dense | 622 928 (432.6) | 1 | 593 568 | 9 233 | - | 335 / 369 MHz | 748 602 | **340** / 519 MHz (datapath) |
| ternary | 168 367 (116.9) | 0.270 | 145 710 | 2 152 | ~7 970 | 332 / 367 MHz | 280 152 | 454 / 633 MHz (control) |
| QC | 164 368 (114.1) | **0.264** | 142 668 | 1 962 | 16 615 | 333 / 369 MHz | 260 235 | 465 / 640 MHz (control) |

* At 4.2 ns, all three meet timing at ss (WNS about 0), so 238 MHz at ss is just the constraint. The tt numbers come
  from a netlist that was sized for ss, so they are also not a real fmax. To get the real fmax, we re-synthesized
  at 2.0 ns.
  * dense is limited by its MAC datapath: 340 MHz at ss.
  * ternary and QC are both limited by the shared control path (M·N compare -> `cstate`) at about 455-465 MHz.
    Their datapaths are faster than that.
* The in-cluster block split (`impl.md`) agrees: dense 9 392 vs QC 2 041 um2 per tile.

## conv1 power and energy (PrimeTime PX, tt, 2.8 ns, SAIF of the busy window)

| SDF tt (reference), WLM | GLS vs model | total mW | array mW | conv1 energy | pJ / dense MAC | vs dense baseline |
|---|---|---:|---:|---:|---:|---:|
| dense, dense ResNet-8 conv1 | bit-exact | 209.0 | 192.9 | 2.85 uJ | 1.207 | 1 |
| dense, s2 conv1 (int8 ternary) | bit-exact | 205.3 | 189.7 | 2.80 uJ | 1.186 | 0.98 |
| ternary, s2 conv1 | bit-exact | **73.6** | 66.3 | **1.00 uJ** | **0.425** | **0.35** |
| QC, s2 conv1 | bit-exact | 81.1 | 74.6 | 1.11 uJ | 0.468 | 0.39 |

| other views, conv1 energy (nJ) | dense base | dense s2 | ternary | QC | QC / ternary |
|---|---:|---:|---:|---:|---:|
| zero delay, WLM (no glitches) | 2 048 | 2 066 | 758 | 774 | 1.02 |
| SDF, zero wire load (same PT setup as M3 / `nn/gls/pt_power.tcl`) | 2 339 | 2 307 | 861 | 928 | 1.08 |

Bit-exactness: all 4 points x {RTL (Verilator), zero-delay GLS, SDF-tt GLS} give 256/256 D tiles exact against the
model (`vectors.py`; the QC codes are cross-checked against `qcacc.model.array`). SDF runs had 0 timing-check
violations and 0 errors.

## Verdict
* **Almost all of the gain comes from removing the multipliers.** Going from dense to QC on the s2 stream saves
  458.6 k um2 of area, and dense -> ternary already accounts for 99 % of that. QC's energy (SDF) is x0.39 of
  dense, and ternary alone reaches x0.35.
* **The butterfly adds little and costs energy.**
  * Area: -2.4 % at 4.2 ns, -7 % at 2.0 ns. QC tiles are 9 % smaller, but most of that is paid back in the 8
    butterflies.
  * Energy: equal without glitches (+2 % at zero delay), but **+10 % with SDF delays**. The deeper chain
    butterfly -> 5-way select -> adders glitches more. The SDF / zero-delay ratio is 1.43 for QC vs 1.32 for ternary.
* **What QC buys over plain ternary is weight storage and traffic, not array energy.** B is 64 b instead of 128 b
  per tile (16 vs 32 B per 8x8 tile, 2x less), and int8 is 8x. This ablation does not capture that, because the
  TB feeds B directly. In M3, the cluster-level RF-macro power fell by 35 % vs the int8 control. Some of that saving
  would also go to a 2-bit ternary cluster.

## Caveats
1. Pre-CTS, ideal clock, wire-load model, no P&R; standalone cores with ideal full-rate inputs (no streamer / TCDM).
2. **Wire load in PT power:** `nn/gls/pt_power.tcl`, used for the M3 / baseline cluster power, never selects a WLM.
   PT therefore falls back to the library default WireAreaForZero (zero wire cap), unlike DC / PT timing. Here,
   zero-WLM power is 14-18 % below WLM power. The M3 absolute mW / pJ numbers are probably low by a similar amount;
   their ratios move only a little. The ablation reports both views and treats WLM as the reference.
3. One layer (conv1), one image; activity depends on the data (dense baseline vs s2 weights: +2 %).
4. Ternary shares x = a - sub_a per row, as QC does. Dense subtracts per tile (upstream, unchanged).
5. fmax: the 4.2 ns runs are bounded by the constraint, and the 2.0 ns ternary / QC runs by shared control logic.
   The datapath fmax difference between ternary and QC is not resolved.

Reproduce: `qcacc/ablation/run.sh [-H tau1]` (all steps; about 40 min). Tables: `ablation_logs/tables.md`;
summaries in `ablation_logs/`.
