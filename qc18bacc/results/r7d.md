# R7d: can the S write-back rotators share one rotator? (measurement; no RTL change)

Labels: **[M]** RTL simulation, **[S]** Yosys, **[A]** argument from the RTL and the schedule.  Build: chip bench, QBT_TECH=2 + `QB_HEAD_FW=128`
+ `QB_HPW=144` (`QB_TOP_WBR=1`, `QB_TOP_SROT=1`, R3B), Verilator 5.050.  Images: E6_s0 val 60 61 0 1 2 and E6_s1 val 13 55 7 42 91,
all PASS (logits 100/100, err 0, 600/600 tiles cycle-exact, wr_conf 0).  Data: `results/r7d/wbstat.txt`, `results/r7d/yosys.txt`.

**Answer: refuted for HQ [M+A]; no RTL change.**  One fused `hm` request writes HQ (lanes 0..15) and, for even y, HQD
(lanes 16..31) in the same cycle (`ef[l]`, `ef[16+l] = !y[0]`; r3a.md section 3): **every HQD cycle is an HQ cycle (160/160
per checkpoint)**, so one HQ/HQD/Z rotator cannot be exact.  Exact pairs: HQD+Z, HQ+Z, HQ + S-read; only the last saves much.

## 1. Co-occurrence and shift amounts [M] (per image, both checkpoints alike)
| class | cycles / image | co-occurs with (cycles, 5 images s0 / s1) | min distance to (cycles) |
|---|---|---|---|
| HQ (hm) | 64 | HQD 160 / 160; nothing else | HQD 0, stream 2, S-read 11, Z 76 / 80, r 404 / 437 |
| HQD (hm, y even) | 32 | HQ only | Z 78 / 82, S-read 13 |
| Z (b6.c1) | 256 | S-read 1161 / 1181 | r 3 / 4, c2 120 / 115 |
| stream 1376, r 256, b6.c2 256; S-read rotator 622 / 659 | | stream: none; r, c2: S-read 384-402 | |

Shifts (`wbstat.txt`): HQ l0 uniform 0..15; HQD bq / Z bz only {0..3, 8..11} (bit 2 = 0 by construction: 3-stage
rotators); S-read s_rot 0..13 (12-15 in < 1 % of its cycles).

## 2. Why the observed exclusions hold by construction [A]
* **HQD vs Z:** both use lanes 16..31 (overlap sets `wr_conf -> err`), and since `wr_d = ew ? dw : df`, a shared rotator
  with Z priority is combinationally identical for every input, conflict cycles included.
* **HQ vs Z, and HQ vs S-read:** these are ordered by the schedule, not by an assertion.  The S port (`s_ren`) carries
  only block-6 int8 loads.  A load needs `l_ok`, which needs (1) the qb_seq stamp of its RAW producer plus its latency and
  (2) `fl_quiet` of the plane's flag bank.  b6.c1 is one whole-map tile reading HQ, so its producer is the last hm tile.
  Z is b6.c1's drain, which comes later still.  The next image's hm can only start after `go`, and `go` is only legal when
  idle (`h_go` while busy sets err).  These orderings are not asserted today.

## 3. Cells and nets per rotator [S] (Yosys 0.68 + slang, generic gates; `impl/r7d/rot.sv`, `hqs.sv`, `wb_srd.sv`)
| block | cells | MUX | nets | note |
|---|---|---|---|---|
| HQ (2048 b + addr, 4 stages) | 8 308 | 8 209 | 6 242 | 128 distinct b/word: **68 % of WB rotator cells** |
| HQD (xd, bq) | 3 139 | 3 080 | 2 109 | 64 distinct b/word (v replicated), 3 stages |
| Z (xz, bz) | 822 | 773 | 558 | 16 distinct b/word (replicated x8), 3 stages |
| WB rotators total | 12 269 | | 8 909 | packing only (shift 0): 1-8 cells |
| HQD+Z shared, 64-b payload, Z priority | 3 497 | 3 395 | 2 451 | **-464 cells (-3.8 %), -216 nets (-2.4 %) of the WB total** |
| S-read group mux + rotator (g_srot) | 10 240 | 10 240 | 8 197 | |
| HQ + S-read shared (3:1 input mux) | 12 297 | 12 292 | 10 260 | **-6 251 cells, -4 179 nets** vs 18 548 / 14 439 |

"~1/3" assumed three equal rotators; replication makes HQD 0.38x and Z 0.10x of HQ, so the best write-back-only share
(HQD+Z, scratch wrapper only) saves < 4 %.  **The large exact opportunity is HQ + S-read:** -28 % cells / -24 % nets of
all four rotators (22 509 / 17 106), for a 2048-b 3:1 input mux and one rotator (by the S macros) feeding the S write
registers and qb_act2 sdq; it relies on section 2's schedule order, so it needs an assertion (`s_ren_d && hm -> err`).
It is outside this task's authorisation and not implemented.

## 4. Files
RTL unchanged.  Bench `hw/tb/tb_qb_chip.sv`: opt-in hook `QBT_WBSTAT` (default build rebuilt, s1 val 13/55 PASS); run as r6a.md
section 5 with `+QBT_WBSTAT`.  `impl/r7d/`: `syn.sh`, `rot.sv` (HQ | HQD | Z | SHZ, NOROT), `wb_srd.sv`, `hqs.sv`.  No tau use.
