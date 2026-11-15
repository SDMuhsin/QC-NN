# R5e: FC weight port 128 b / cycle on one dense macro (`qb_head` FW = 128)

Labels: **[S]** synthesis / STA / macro compiler, **[M]** simulation, **[Mod]** cycle model, **[E]** estimate.
Small summaries are in `results/r5e/`. Kit files (macro views, netlists, reports) stay on tau:
* tau5 / usask `/tmp/ckp908/qcnn/macros/qb_f_3232x128m8`;
* tau5 `/tmp/ckp908/qc18bacc/build/syn/r5e_head{256,128}`;
* usask `/tmp/ckp908/qc18bacc/build/syn/r5e_chip`.

**Result.**
* The head FC runs at 16 int8 MAC / cycle from one `sram_sp_adv 3232 x 128 mux 8`: **0.466 mm2 [S]**, against
  16 x rf_sp 408 x 64 = 0.766 mm2. That is **-0.300 mm2 of macros**.
* Head logic: **-0.016 mm2 [S]**.
* **0 cycles.** The image interval stays the static model + 1 [M]. The head still fits inside every interval of
  val[:300] of both seeds [Mod]. The worst-case margin is 246 cycles before the next image's first pq write.
* Logits are torch.equal to IntBin2 on all 6 bench images [M].
* Both mutants in the new FC path are caught.

## 1. Head cycles vs the image interval [Mod, M]

Script: `impl/r5e/head_slack.py`. It imports `compile/static_seq`. Output is in `results/r5e/slack.txt`. Data:
E6_s0 and E6_s1 val[:300], each with 1 commit order.

**FC rows at 128 b.**
* Per group of 4 classes there is one bias row (4 x int32), then 4 x 32 weight rows.
* That gives 25 + 3 200 = **3 225 rows** (256 b: 13 + 1 600 = 1 613).
* The head ends (last logit / FC done) at go(i+1) **+3 250**, against +1 638 at 256 b. This is +1 612, which is
  exactly the extra row count. The bench measures 3 250 on all 6 images.

| seed | interval M+1 min / mean / max | (a) interval - head 3 250: min | first pq write of image i+1 (go + T7 + 21) | (b) RTL constraint: pq write - FC done, min / mean / max | 256 b (b) min |
|---|---|---|---|---|---|
| E6_s0 | 3 652 / 3 776.0 / 3 900 | **402** (300 / 300 fit) | T7 = M - 128 on every image | **294** / 418 / 542 (300 / 300) | 1 906 |
| E6_s1 | 3 604 / 3 754.1 / 3 884 | **354** (300 / 300 fit) | | **246** / 396 / 526 (300 / 300) | 1 858 |

**Constraints.**
* (a) is the brief's criterion: the head must finish within the next image's interval.
* (b) is the binding constraint in the RTL. FC i reads pq, and image i+1's b7.c2 overwrites pq, so FC i must be
  done before that first pq write (qb_head `err`). It is 107 cycles stricter than (a).

**Inputs to (b).**
* T7 is the drain start of the first b7.c2 tile in the static model. It is always M - 128.
* The +21 offset from T7 to the first pq write was measured on the bench and is the same on all 4 transitions: for
  example, s0 img 1 has its first pq write at go + 3 680, with T7 = 3 659.
* The bench slacks 430 / 454 (s0 0->1, 1->2) and 406 / 446 (s1 13->55, 55->91) equal the model's numbers for those
  images.

**Shortest image.** The minimum interval is s1 val 246 (3 604). It leaves 354 / 246 cycles of margin under (a) / (b).

**Untested.** Images faster than about 3 475 + 128 cycles would break (b). None occur in 600 images, but there is no
proof for test or for other checkpoints. If a future cycle cut shortens images by more than about 240 cycles, the
cheapest fixes are:
* start the FC at the last pq write of the chunk it needs, instead of at pool done;
* or double-buffer pq (3.6 k flops, about +0.025 mm2 [E]).

## 2. Macro [S]

Script: the existing `impl/mem/mc_sweep.sh`, run on tau6. Shapes are in `impl/r5e/shapes_fc128.txt`. Raw numbers
are in `impl/r5e/sweep_fc128_raw.txt`.
* Need: 3 225 rows x 128 b, read at 128 b / cycle.
* Gate (same as mem.md): 500 MHz tt, meaning lib ta_tt <= 1.2 ns and tcyc_tt <= 2.0 ns.

| config | macros | mm2 [S] | tt ta / tcyc ns | ss ta / tcyc ns |
|---|---|---|---|---|
| **sram_sp_adv 3232 x 128 mux 8** | **1** | **0.466** | 0.917 / 1.136 | 1.439 / 1.861 |
| sram_sp_adv 3232 x 64 m8, 2 lanes | 2 | 0.509 | 0.777 / 0.989 | 1.219 / 1.617 |
| sram_sp_adv 3232 x 64 m16, 2 lanes | 2 | 0.571 | 0.911 / 1.125 | 1.431 / 1.865 |
| sram_sp_adv 1616 x 128 m8, 2 deep | 2 | 0.571 | 0.894 / 1.101 | 1.402 / 1.807 |
| sram_sp_adv 3232 x 32 m8, 4 lanes | 4 | 0.595 | 0.719 / 0.938 | 1.131 / 1.535 |
| sram_sp_adv 1088 x 128 m8, 3 deep | 3 | 0.724 | 0.886 / 1.090 | 1.389 / 1.789 |
| rf_sp_adv 464 x 64 m4, 2 lanes x 7 deep | 14 | 0.709 | 0.744 / 0.663 | 1.215 / 1.079 |
| rf_sp_adv 408 x 64 m4, 2 lanes x 8 deep | 16 | 0.766 | 0.734 / 0.653 | 1.197 / 1.055 |
| (as built, 256 b: rf_sp 408 x 64 m4, 4 x 4) | 16 | 0.766 | | |

**Choice.** `qb_f_3232x128m8` (`impl/r5e/macros.txt`, generated with `flow/tsmc65/sram/mc_gen.sh gen` on tau5 and
usask): 1.13 um2/bit, against 1.86 um2/bit before.
* At 128 b / cycle a single deep mux-8 SRAM meets the port. The 256-b port had forced 16 shallow register files.
* Its tt access is 0.917 ns. That is slower than the rf (0.734 ns), but it now feeds the output register with no
  4:1 depth mux in between.
* At the chip target of 1.65 ns tt it is not critical (section 4).

## 3. RTL (defaults unchanged)

**`hw/rtl/qb_head.sv`**
* New parameter `FW` (default 256). Derived: NMAC = FW / 8, NM = NK / NMAC rows per class, G = FW / 32 classes per
  bias row, `NFR` / `AW` (row address width) defaults depend on FW.
* The FW = 256 macro block (4 x 4 rf_sp, depth mux) is unchanged, inside `g_f256`.
* FW = 128 (`g_f128`) uses one `qbt_rfsp #(128, 3232)`, with the same address register -> macro -> output register
  boundary, so the row still arrives at x + 3.
* Sequencer, MAC loop, HP two-stage tree (NMAC / 2 per partial sum), bias-row grouping and lo_vld are written in
  NMAC / NM / G. These reduce to the old constants at 256.

**`hw/rtl/qb_chip.sv`**
* Define `QB_HEAD_FW` (default 256).
* At 128, FC rows 0..2047 are written with h_sel 16 and rows 2048.. with h_sel 18 (row = {h_sel == 18, h_addr}). h_sel
  18 was unused, so the host port width is unchanged.
* Head configuration word 7 (FC rows) is 12 b.

**Tech mapping**
* `hw/tech/qb_mem_tech.sv`: `qbt_rfsp 128 x 3232` maps to `qb_f_3232x128m8`.
* `hw/tech/qb_mem_arm_beh.sv`: local pin stand-in.
* `hw/tech/qb_chip_tech_r5e.f`: the R4b list plus `QB_HEAD_FW=128`.

**Bench and flow**
* `hw/tb/export_top3.py --fc 128` (default 256): writes the 128-b rows.
* `hw/tb/tb_qb_chip.sv`: rows >= 2048 go through h_sel 18. No 256-b program has that many rows.
* `impl/r4/run.sh`: optional `QB_MACROS_EXTRA` adds more macro lists to link.

Run:
```
QB_TB_WORK=W QBT_DEFS=+define+QB_HEAD_FW=128 qc18bacc/hw/tb/run_tb_chip.sh build      # behavioural
QB_TB_WORK=W QBT_TECH=2 QBT_DEFS=+define+QB_HEAD_FW=128 qc18bacc/hw/tb/run_tb_chip.sh build   # R4b tech (HP=1)
CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_top3.py RUN/best.pt OUT --cache DIR --images ... --fc 128 [--check]
```

## 4. Verification [M]

Summary lines are in `results/r5e/tb.txt`. Each run streams 3 images back to back through one program load.

| build | E6_s1 val 13 / 55 / 91 | E6_s0 val 0 / 1 / 2 |
|---|---|---|
| FW 128 behavioural (HP 0) | PASS, torch.equal x 3 | PASS, torch.equal x 3 |
| FW 128 R4b tech (HP 1, ARM pin models) | PASS, torch.equal x 3 | PASS, torch.equal x 3 |

Every image in both FW 128 builds:
* 600 / 600 tiles cycle-exact;
* interval = M + 1 (3 836 / 3 764 and 3 748 / 3 788);
* err 0;
* last logit at end + 3 250.

**Regression (FW 256 default).**
* The behavioural and R4b tech builds pass on s1 13 / 55 / 91 with torch.equal.
* Head at end + 1 638 (= R3c / R4b); overlap slack 2 018 / 2 058 (= R3c).
* Standalone DC of the default head: 0.193 mm2 logic, against 0.194 mm2 for the head in the R4b chip run.

**Mutants (FW 128, s0 val 0 / 1 / 2): 2 / 2 caught.**

| mutant | fault | result |
|---|---|---|
| `QBC_MUT_FHI` (new host path) | upper FC rows (h_sel 18) written to {0, h_addr}: they overwrite rows 0..1 176 | FAIL: 77 / 100 logits wrong on every image |
| `QBH_MUT_FCK` (FC datapath, NM = 32) | chunk m of W multiplies chunk m ^ 1 of pq | FAIL: 100 / 100 logits wrong on every image |

## 5. Synthesis [S]

DC W-2024.09 topographical tt at 1.65 ns, using the R4b recipe: `impl/r4/run.sh syn`, `impl/r4/constraints.sdc`,
file list `qb_chip_tech_r4b.f`, top `qb_head`, HP = 1. PT runs on the DC parasitics. Summaries are in
`results/r5e/dc_head{256,128}.txt`.

| qb_head (standalone) | logic um2 | macros um2 | total | regs | DC WNS @1.65 | PT fmax tt / ss |
|---|---|---|---|---|---|---|
| FW 256 (= R4b) | 193 119 | 765 949 (16) | 959 068 | 7 582 | +0.000 | 693.0 / 449.8 MHz |
| FW 128 | 177 290 | 466 267 (1) | 643 557 | 7 202 | +0.002 | 693.4 / 448.2 MHz |
| **delta** | **-15 829** | **-299 682** | **-315 511** | -380 | | |

**Timing.** At both widths the worst head path is the pool requant lane (m0 -> p1), not the FC. Head fmax stays well
above the chip's 601 / 376 MHz pre-route.

**Where the logic saving comes from.** The MAC and tree have half the products (16), there are fewer xs flops, and
the 4 x 4 depth mux and its address logic are gone. It is partly offset by the wider row counters.

**Chip pre-route [S].** Whole-chip DC of `qb_chip_tech_r5e.f` (usask, 2 h 14 min, the R4b recipe). Summary in
`results/r5e/area_chip.txt`.

| | R4b run d | R5e chip | delta |
|---|---|---|---|
| logic | 7.879 | 7.874 | -0.005 |
| of which head | 0.194 | **0.177** | **-0.017** |
| of which other blocks | | | +0.012 (DC noise; core +0.019, R4b runs d / b differ by 0.021) |
| macros | 7.248 (119) | **6.948 (104)** | **-0.300** |
| **chip** | **15.127** | **14.823** | **-0.304 mm2 (-2.0 %)** |

* The DC compile closes at 1.65 ns: final WNS 0.00, as R4b.
* **No chip PT [negative].** The usask disk filled up (shared, 100 %) while DC wrote its outputs. The .ddc survived,
  but the .sdc / .spef and the reports came out empty, and the area above is re-reported from the .ddc
  (`impl/r5e/ddc_area.sh`). The head-level PT (above) shows the head is not near the chip's critical paths.

**Routed [E]** (r4b.md factors: logic x 1.47, macros x 1.15): -0.37 mm2 of about 19.9, i.e. -1.9 %. At the R4b
estimate (@473 MHz, avg 1.51) that is about **avg 1.54 TOPS/mm2** at 0 cycles. The bigger macro is a single
1 184 x 394 um block, so its placement next to the head is a floorplan item for R5b.

## 6. Deviations / notes
1. **The binding constraint is (b), not the interval.** pq is single-buffered, so the FC must finish before the next
   image's b7.c2 starts. The margin is 246 cycles on s1 val[:300] [Mod]. Before R5e it was about 1 860.
2. **One macro now holds all FC weights.** It is 0.47 mm2, with no redundancy.
3. **Host FC load takes 3 225 writes** instead of 1 613. This is a once-per-network program load.
