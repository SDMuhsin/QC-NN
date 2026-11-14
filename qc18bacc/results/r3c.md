# R3c: image to logits (`qb_chip` = `qb_top` R3B + head `qb_head` + host port)

New files:
* RTL: `hw/rtl/qb_head.sv` (pool + FC), `hw/rtl/qb_chip.sv` (chip top, host port).
* Bench: `hw/tb/export_top3.py` (export + `--check`), `hw/tb/tb_qb_chip.sv`, `hw/tb/run_tb_chip.sh`.

Default-off hook: `qb_top #(HSEL = 0)` and `qb_prm #(HSEL = 0)` (section 2). Nothing else in the existing files
changed. Raw lines are in `results/r3c_tb.txt`. Labels: [M] simulation, [Mod] model, [S] macro compiler, [E] estimate.

```
CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_top3.py RUN/best.pt OUT --cache DIR --images 0 1 2
QB_TB_WORK=W qc18bacc/hw/tb/run_tb_chip.sh build && QB_TB_WORK=W qc18bacc/hw/tb/run_tb_chip.sh run OUT/prog OUT/img0 OUT/img1 OUT/img2
CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_top3.py RUN/best.pt OUT --cache DIR --images 0 1 2 --check
```

## 1. Head (`qb_head`): exact IntBin2 semantics

* `pq = requant(sum_16px relu(s7), pool_m0, pool_sh, 0, 127)`.
* `lg = pq . W8^T + fbq`, int32.
* IntBin2's float logits are `lg x fscale` (per class, fp64). This scale sits outside the integer datapath, so the
  host applies it. The check is `torch.equal(rtl.double() * fscale, IntBin2(x))`.

**Pool: no S re-read and no image cycles.**
* qb_head taps qb_top's fused write-back bus of the last pass (b7.c2, the existing `dbg_f*` ports) in the same cycle
  as the S write request.
* Per drain step it adds the ReLU of 4 px x 64 ch into a 64 x 19-b tile accumulator.
* At step 3 the tile's 64 sums are complete (one b7.c2 tile = 16 px x 64 ch). They move to a hold register.
* 4 requant lanes convert the 64 sums in 16 cycles into `pq` (512 x 7-b register). The lanes are instances of
  qb_core's `qbcw_lane`, in u8 mode, with m0 / sh from the head configuration.
* b7.c2 tiles are at least 16 cycles apart, and an overrun is flagged as err.
* Why dedicated lanes instead of the wide lanes: the wide-lane option needs a pool-input mux on all 32 wide lanes
  plus a pool record in the params program, or about 2.5 k mux bits of parameter override. That is about 2 to 7 k um2
  [E] against about 25 to 37 k um2 for 4 lanes (r1.md: 9 199 um2 per full lane [S]; the tie-offs prune bias, r and T).
  It also touches the wide lane's S0, a near-critical path (pnr_slice2.md), and qb_prm's program. So this is not the
  cheapest exact unit: it costs about 0.02 to 0.03 mm2 more, chosen to keep qb_core and qb_prm unchanged. The
  wide-lane hook is the R4 option.

**FC.** The FC macro is a behavioural model of the mem.md e_fc shape at 256 b / cycle:
* rf_sp 408 x 64 mux 4, 4 lanes x 4 deep = 1 632 rows. These are the same 16 macros as the 512-b arrangement:
  0.766 mm2 [S], already in the 7.07 mm2 macro total.
* Boundaries are registered: request x, then address register, then macro, then output register; the row arrives at
  x + 3.
* Rows: per group of 8 classes, one bias row (8 x int32), then 8 x 16 weight rows. 1 613 rows in all, 1 per cycle.
* 32 MACs (7 b x int8) feed an adder tree into a 20-b partial sum, then a 32-b accumulator. One class comes out every
  16 cycles on `lo_vld / lo_idx / lo_val`.

**Overlap.** The head of image i runs while image i + 1 computes. The head shares no port with the engine:
* it reads the fused bus only;
* it has its own lanes, FC macro and pq.

The only state shared between images is pq. It is written by image i + 1's b7.c2 and read by FC i.

Checks in RTL (err):
* pq write or pool done while the FC is busy;
* requant overrun;
* host contract violations: h_go while busy, an IMG write while the IMG is not free.

Measured slack between FC i done and image i + 1's first pq write: **1 954 to 2 066 cycles** [M]. Image i's pool
tail runs 21 cycles into image i + 1 on head-only resources, with no conflict.

## 2. Host port (`qb_chip`)

**Inputs**
* One write per cycle: `h_we, h_sel[4:0], h_addr[10:0], h_data`.
  * h_sel 0..15: the qb_top memories as in R3b (weights, params bank, IMG lines, pass table, pass lists, load
    permissions, descriptors, fetch lists, counts).
  * h_sel 16: FC row.
  * h_sel 17: head configuration (pool m0 / sh, last pass, last-pass outputs, stem pass, stem tiles, classes, FC
    rows; `prog/head.txt`).
* `h_go`: start the image held in IMG.

**Outputs**
* Status: `st_idle`, `st_img_free`, `st_head_busy`, `err`.
* Logits stream: `lo_vld / lo_idx / lo_val`.

**Program.** It is loaded once per network. Streaming: load image 0, then h_go. When `st_img_free` rises, which is
after the stem's last tile end, at +275 cycles [M], load image i + 1 (128 lines). Give h_go in the cycle `st_idle` is
seen.

**IMG is not double-buffered** (saves 0.135 mm2, mem.md). The stem reads IMG for the first 275 cycles only. The next
image is loaded during the remaining ~3 400 cycles, so the single buffer **costs 0 cycles** [M].

**Port conflict found and fixed (hook HSEL).** In qb_top / qb_prm, every behavioural macro's address mux switched to
`h_addr` on *any* `h_we`. A host IMG write during compute therefore redirected the weight and params reads. HSEL = 1
(set by qb_chip) switches a macro to the host address only on a write to that macro. Mutant HSEL (the old muxing)
breaks images 0 / 1, whose successors were loaded during them, and image 2 (no load during it) passes. That confirms
the mechanism.

## 3. Bench [M]: back to back through one program load per seed

* Logits: all 100 int32 classes per image vs IntBin2, plus the `torch.equal` check in Python.
* Every array tile end of every image is checked cycle-exact against that image's static-order model.
* No IMG read occurs while `st_img_free`, and `err` = 0.

| seed | val | logits (torch.equal) | tiles cycle-exact | RTL image end / model M | interval to next go | go to last logit |
|---|---|---|---|---|---|---|
| E6_s0 | 0 | **PASS** | 600 / 600 | 3 748 / 3 747 | 3 748 | 5 386 |
| E6_s0 | 1 | **PASS** | 600 / 600 | 3 788 / 3 787 | 3 788 | 5 426 |
| E6_s0 | 2 | **PASS** | 600 / 600 | 3 812 / 3 811 | 3 812 | 5 450 |
| E6_s0 | 3, 4 (extra) | **PASS** x 2 | 600 / 600 | M + 1 | M + 1 | M + 1 + 1 638 |
| E6_s1 | 7 | **PASS** | 600 / 600 | 3 732 / 3 731 | 3 732 | 5 370 |
| E6_s1 | 42 | **PASS** | 600 / 600 | 3 796 / 3 795 | 3 796 | 5 434 |
| E6_s1 | 88 | **PASS** | 600 / 600 | 3 700 / 3 699 | (last) | 5 338 |

**Steady state.** The interval is exactly **M + 1 cycles per image**, where M is the static-order model.
* Mean over val[:100] [Mod]: **3 777.4 (s0) / 3 759.0 (s1)**. Image dependence comes from the block-6 flags.
* The +1 is R3a's write-back tail: h_go lands in the cycle of the last macro write, and the next image's now = 0 is
  the cycle after.
* The head adds 0 cycles to the interval.

**Latency** (go to last logit) = M + 1 + **1 638**. The model's head is 1 620 (`cycles.head_cycles`: pool 16 + FC
1 604). The +18 breaks down as:

| item | cycles |
|---|---|
| bias rows (1 per 8 classes, single-port FC macro) | +13 |
| requant-lane latency | +4 |
| pool done / FC start registers | +2 |
| one fewer FC pipeline stage than the model's FC_LAT 4 | -1 |

The head fits about 2.2x inside the shortest image (3 651 [Mod]).

**Mutants** (E6_s0 val 0 / 1 / 2 streamed): **4 / 4 caught.**

| mutant | fault | result |
|---|---|---|
| RELU (pool) | ReLU dropped in the pool sum | FAIL: 100 / 100 logits wrong on every image |
| FCK (FC) | FC multiplies chunk m of W by chunk m ^ 1 of pq | FAIL: 100 / 100 logits wrong on every image |
| HSEL (port) | host address muxing of R3a / R3b (IMG load redirects weight / params reads) | FAIL: images 0 / 1, logits wrong, 40 b6 tiles off-cycle |
| IMGF (port) | `st_img_free` raised at go (next image overwrites IMG during the stem) | FAIL: 384 IMG reads flagged, logits wrong, 9 / 40 tiles off-cycle |

**Regressions [M]: all pass.**
* `run_tb_core.sh`: PASS, 3 644 / 3 684 cycles.
* `run_tb_act2.sh`: PASS, 600 / 600 tiles.
* qb_top R3a default build on r3a/img0: PASS, 3 748.
* qb_top R3B build on r3b_s0 img0 / img1 and r3b_s1 img7: PASS, 3 748 / 3 788 / 3 732.
* `compile/test_compile.py --n 100`: ALL PASS. compile/ is unchanged.

## 4. Head area [E]

Yosys 0.68 generic synthesis of qb_head, with the FC macros as black boxes. Cell counts are converted at TSMC 65 GP
cell areas. This is not DC; DC with real adders is typically smaller.

| part | count | area |
|---|---|---|
| total | 66.9 k cells | **about 0.21 mm2 logic** |
| flops | 7 100 | about 0.06 mm2 |
| pq register | 3 584 flops | |
| pool tile accumulator + hold | 2 432 flops | |
| combinational: 4 requant lanes, 64 four-input ReLU adders + accumulators, 32 MACs + tree, pq read mux | | about 0.15 mm2 |

* Routed at x 1.7: about 0.36 mm2. The FC macro adds 0.766 mm2 [S], already counted in the 7.07 mm2.
* Cheaper R4 options: pq in a small rf_sp, or 6 lanes and no hold (-21 k um2 of flops); the pool on the wide lanes
  via a qb_core hook (about -0.02 mm2).
* Head ops are not counted in executed TOPS. FC is 51 k MAC per image, against 119.9 M in the conv layers.

## 5. Deviations / open items

1. **Logit scale on the host.** The chip outputs int32 `lg`. IntBin2's float logits are `lg x fscale` (per-class
   fp64), applied host side. argmax over float logits needs that scale.
2. **The pool taps qb_top's existing `dbg_f*` ports** (the fused write-back bus). These are functional outputs now;
   R4 should rename them. Image end and IMG free come from the same taps: last-pass output count and stem tile-end
   count, both from the head configuration.
3. **No tail overlap between images.** The next h_go waits for the last write of the image (+1 cycle vs M). Starting
   at the last commit would save about 20 cycles (0.5 %), but go resets qb_seq / qb_prm and the next stem's S writes
   would race the b7.c2 tail.
4. **Pool requant uses 4 dedicated lanes, not the wide lanes** (section 1). This costs about 0.02 to 0.03 mm2.
5. **The ARCH head line says FC 64 MAC / cycle**; v1.2 / mem.md say 256 b / cycle = 32 MAC / cycle. The build uses
   32 MAC / cycle as briefed.
6. **Host-side bandwidth assumed** at 512 b / cycle for the image load (128 cycles). Any rate that finishes within
   about 3 400 cycles costs nothing.
