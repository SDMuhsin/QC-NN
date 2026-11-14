# R3b: image-independent sequencer + real params path for `qb_top`

New files:
* RTL: `hw/rtl/qb_seq.sv`, with modules `qb_seq` (the sequencer) and `qb_prm` (the params path).
* Bench vectors: `hw/tb/export_top2.py`.
* Model: `compile/static_seq.py` (the static order, an event-level mirror of the RTL engine, and the program build).

Default-off hooks in existing files:
* `qb_top #(R3B = 0)`. R3B = 1 swaps in qb_seq and qb_prm. The pass table grows from 89 to 96 b; bits [93:89] hold
  the per-pass common pf / pw bits.
* `cycles.list_schedule(order=None, rec=None)`: forced static issue order, and recording of the commit order.
* `tb_qb_top.sv`: `+define+QBT_R3B`, which loads the program from `+prog=`.
* `run_tb_top.sh`: adds qb_seq.sv to the build and passes `QBT_PROG`.

Raw lines are in `results/r3b_tb.txt`. Labels: [M] measured (simulation), [Mod] model, [S] macro compiler on tau,
[E] estimate.

```
CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_top2.py RUN/best.pt OUT --cache DIR --images 0 1
QB_TB_WORK=W QBT_DEFS=+define+QBT_R3B QBT_TAG=_r3b qc18bacc/hw/tb/run_tb_top.sh build
QB_TB_WORK=W QBT_PROG=OUT/prog QBT_TAG=_r3b qc18bacc/hw/tb/run_tb_top.sh run OUT/img0 OUT/img1
```

## 1. Sequencer (open item 1 of R3a)

**Static order.** The free list scheduler (config C, `lat`, `bub`) commits all 616 tiles in **one and the same order**
on every image of val[:100], for both seeds [Mod]:
* only the block-6 durations vary between images;
* they never flip a scheduling decision.

That order is the network's issue order. Forcing it (hook `order`) gives these cycles:

| seed | free list schedule | static order | delta on val[:100] |
|---|---|---|---|
| E6_s0 | 3 776.44 | 3 776.44 | 0 on 100 / 100 images |
| E6_s1 | 3 758.04 | 3 758.04 | 0 on 100 / 100 images |

So no hook-induced cycle delta exists. The descriptor files for s0 and s1 are identical except the pass table
(params bits).

**Hardware (`qb_seq`).** The host loads one program per network (68.5 kb):
* 616 tile descriptors of 80 b in commit order;
* 286 load-permission entries;
* two context pass lists.

At run time, gating replaces R3a's per-image timestamps:
* **Stamp scoreboard.** One entry per committed tile holds the time its writes are done: de, or the capture for c1.
  A valid bit is cleared at go.
  * An array RAW hazard waits for `stamp[rasdep] + lat`.
  * A drain-time read (the r of b2/b4.sc into c2, s into hm) waits for `stamp[rdsdep] + lat`.
  * rasdep is a static pointer to the producer tile committed last. Producers of one pass drain in order, so that
    tile's stamp is the maximum.
  * WAR / WAW hazards are not gated. They are implied by the in-order array and lane FIFOs plus the RAW chain.
    Dropping them changes no time on the 200 images checked.
* **Commit engine (end pointer).** An array tile ends at its ce, which is d_vld & d_eot of the act supply. Then:
  * cap = max(ce, t_sh);
  * ds = max(cap, lane, rw);
  * de = ds + 4 / 32.

  hm tiles end when the pointer reaches them: ds = max(lane + bub, rw), plus OVH on the first tile of the pass. The
  engine takes one tile per cycle. Capture and PPU-job events fire at cap / ds, through a 1-entry capture register and
  32 / 8-deep job FIFOs.
* **Tile token (start pointer).** A tile gets its token in the first cycle where all of these hold:
  * the previous array tile has ended;
  * now >= t_arr;
  * now >= ra (+ OVH at a pass switch);
  * for drained tiles, now + C >= t_sh. This is the model's just-in-time start.

  C is static for binary tiles. For block 6, C is the popcount of the writer-side slice flags, which are final before
  ra.
* **Act-supply contexts.**
  * The next pass on a context starts the cycle after that context's done pulse.
  * Load permissions come from static entries (pos, rasdep, lat, age). For int8 passes, pos = (j + 1) x the
    executed S words, computed from the flags.

`compile/static_seq.emulate` mirrors this engine at event level. Against the forced-order model it gives 0 time
mismatches and 0 "needed before known" events on 100 images x 2 seeds [Mod].

## 2. Params path (open item 2)

Demand comes from the static order's use sequence. Each fused drain / hm job takes a 64-channel pf set (5 184 b of
records); each wide drain takes pw (5 056 b); each c1 capture takes T2 (1 088 b). Fused sets alternate per tile:
there are 156 fused set runs per image. A fetch model (staging free 2 cycles before its set's last use, staging valid
3 cycles after the request, one bank row per cycle) gives these late-set counts on val[:100] for both seeds [Mod]:

| bank row (b / cycle) | rows per pf set | late sets |
|---|---|---|
| 110 / 220 (the v1.2 macro / 2 x 1952x110) | 48 / 24 | every image, unbounded |
| 1 152 | 5 | every image, up to 26 to 32 cycles |
| **1 296** (fused double-buffered) | 4 | **0** |
| 1 296 (fused single-buffered) | 4 | late in RTL (mutant PRM1, img0). Single-buffered is late by 2 to 3 cycles on every image even at 1 440 to 1 760 b [Mod] |

**Chosen design (`qb_prm`):**
* Bank: **9 x rf_sp_adv 240 x 144 mux 2**, read in parallel. A row is 1 296 b; 238 / 240 rows are used.
* Sets: a pf or pw set is 4 rows, a T2 set is 1 row. The common bits sit in the pass table.
* Static fetch lists per consumer, 286 x 25 b: {uses, base row, tag}.
* Priority T2 > fused > wide.
* Staging registers: fused 2 x 5 184 b, wide 1, T2 1. They are the macro output registers.
* Each use checks valid + tag, and `err` flags a miss.

**Cycle cost: 0** [M]: identical cycles, and err stays 0.

**Margin: 0.** A 4th pipeline stage would make one set late by 1 cycle on every image [Mod]. If R4 needs that stage,
free the staging register at stage D - 1 instead of D (the delay line already exists).

Area [S] (ARM compiler on tau-02, `impl/mem/mc_sweep.sh`, shapes in `impl/mem/shapes_r3b.txt`):

| params | macro um2 | total mm2 | b / cycle | tt ta / tcyc ns | ss ta / tcyc ns |
|---|---|---|---|---|---|
| v1.2: sram_sp 3904 x 110 m8 x 1 | 455 897 | 0.456 | 110 | 0.882 / 1.104 | 1.385 / 1.805 |
| **R3b: rf_sp 240 x 144 m2 x 9** | 59 602 (440 x 136 um) | **0.536** | 1 296 | 0.787 / 0.690 | 1.283 / 1.115 |
| alt: rf_sp 184 x 144 m2 x 12 | 53 444 | 0.641 | 1 728 | 0.767 / 0.670 | 1.248 / 1.081 |
| alt: rf_sp 184 x 110 m2 x 16 | 42 675 | 0.683 | 1 760 | 0.710 / 0.622 | 1.158 / 1.005 |

* **Macro delta: +0.081 mm2 (+17.7 %)**. Total macros go from 7.07 to 7.15 mm2.
* Staging flops: about +5.5 kb versus R3a's pf_q / pw_q / t2_q, which is roughly 0.03 to 0.04 mm2 [E].

## 3. Bench [M]: same full-image checks as R3a

The checks cover every core output, every act item / eot, every tile end cycle-exact, the final S, and err. Each seed
uses one program for all of its images.

| image | checked | tiles cycle-exact | RTL end | static-order model (= free) | result |
|---|---|---|---|---|---|
| E6_s0 val 0 | 633 664 | 600 / 600 | 3 748 | 3 747 | **PASS** |
| E6_s0 val 1 | 633 704 | 600 / 600 | 3 788 | 3 787 | **PASS** |
| E6_s0 val 2..9 (extra) | 633 616 to 633 728 | 600 / 600 each | model + 1 | 3 699 to 3 811 | **PASS x 8** |
| E6_s1 val 7 | 633 648 | 600 / 600 | 3 732 | 3 731 | **PASS** |
| E6_s1 val 42 | 633 712 | 600 / 600 | 3 796 | 3 795 | **PASS** |

The +1 is R3a's fixed write-back tail. RTL equals R3a on images 0 / 1: 3 748 / 3 788.

**Mutants** (E6_s0 img0, `+define+QBT_MUT_x`): **5 / 5 caught.**

| mutant | fault | result |
|---|---|---|
| SB (scoreboard) | tile token ignores the stamp gate (ra = 0) | FAIL: 24 012 errors, 40 tiles off-cycle, err set; b6.c1 items wrong first |
| LOK (scoreboard) | load permission ignores the stamp gate | FAIL: 341 241 errors, 478 off-cycle, err set; b0.c1 reads stale B1 |
| RDS (scoreboard) | drain-read RAW (rdsdep) ignored | FAIL: 136 626 errors, 228 off-cycle; b2.c2 reads r before b2.sc wrote it |
| PRMR | params: the rows of a fused set land swapped | FAIL: 445 371 errors |
| PRM1 | params: fused consumer single-buffered | FAIL: set late (err), 120 878 errors |

**Regressions [M]:** all pass.
* `run_tb_core.sh`: PASS, 3 644 / 3 684 cycles.
* `run_tb_act2.sh`: PASS, 600 / 600 tiles.
* qb_top default build (R3B = 0) on the R3a vectors: PASS, 3 748 cycles.
* `compile/test_compile.py --n 100` (both seeds, hooks present, defaults unchanged): **ALL PASS**.

## 4. Deviations / open items

1. **Token path is combinational within the cycle.** When a tile starts the cycle its predecessor ends, the chain is
   d_eot to the end phase, then the start compare, then tgo, then qb_act2's issue. In R3a this was a timestamp
   compare. R4 should retime it by evaluating the start condition one cycle ahead: a binary tile's end is known C
   cycles ahead, and the int8 issue sequencer knows its last item.
2. **Program memories are behavioural flop arrays with several read ports**, about 69 kb of program plus a 10.5 kb
   stamp table:
   * descriptors are read at ke and ks;
   * load-permission entries are read 2 per context;
   * stamps are read by the engine and both contexts.

   Mapping these to rf macros (prefetch registers, since both pointers advance at most 1 per cycle) is R4 work.
3. The hardware gates RAW only. WAR / WAW and the c1 `rw - C` term are structurally implied (checked, not proven,
   beyond the 200 model images and 12 RTL images). An image whose free schedule would pick another order still runs
   correctly on the static order; its cycles are what the `order` hook models.
4. Block-6 C and S-word counts come from qb_top's sticky flag-hit sets, not from qb_act2's flag store. The hits are
   the same.
5. Params margin is 0 cycles at the current pipeline depth (section 2).
6. No synthesis yet (R4). The head is still open.
