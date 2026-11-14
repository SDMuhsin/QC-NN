# R3a: top-level integration `qb_top` + full-image bit-exact bench

RTL: `hw/rtl/qb_top.sv` (new). Bench: `hw/tb/export_top.py` (descriptors + init image; imports export_core /
export_act / supply / cycles), `hw/tb/tb_qb_top.sv`, `hw/tb/run_tb_top.sh`. Compiler: two default-off hooks in
`compile/cycles.list_schedule` (`lat`, `bub`, see section 3). Raw lines: `results/r3a_tb.txt`.
Labels: [M] measured (simulation), [Mod] modelled.

```
CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_top.py /tmp/root/qc18b/exc200/E6_s0/best.pt OUT --cache DIR [--dist 1]
qc18bacc/hw/tb/run_tb_top.sh build && qc18bacc/hw/tb/run_tb_top.sh run OUT/img0 OUT/img1
```

## 1. What is built

* `qb_core #(CREG 1, WTP 1, FTP 1, PPOP 1, BRG 2)` and `qb_act2` (config C, ACT_PIPE 1), both unchanged.
* **Act distribution:** `DIST` full-bus register stages (default 1) between qb_act2 and the core. Codes and item
  controls are delayed to match: D = 2 + AP + DIST, so an item issued at i has its codes and ctl at i + D and its act at
  i + D + 1.
* **Behavioural macros, chosen geometries, registered boundaries:**
  * weights: rf_sp 204x144 x48 (16 lanes x 3 deep, 611 rows of 2304 b);
  * S: rf_2p 256x128 x32 (1R+1W, 16-b entries);
  * B1, B2: rf_2p 128x128 x4 each; IMG: rf_sp 128x128 x4;
  * same-address read and write in one cycle gives X and raises `err`.
* **Sequencer:** time-triggered descriptor queues, loaded through a host port. Contents:
  * a pass table;
  * pass commands per context, tile tokens, captures (cap / cmp);
  * fused-unit jobs (drains and hm), wide drains;
  * per-pass load-permission tables (position, RAW-ready, age).
  Each event fires when `now` equals the model time. From each event, fixed delay lines generate every core port:
  ctl, cd, T2, PPU controls, pf / pw, s_rd / w_r reads and write-back tags. Size: 21 / 20 / 600 / 600 / 360 / 24 /
  286 entries, about 57 kb per image.
* **Write-back:**
  * fused stream in place, flat stream layout;
  * b1_next as 2 full map words per cycle;
  * b2 through a 2-deep FIFO, one map line per cycle (2 lines, 4 at W = 4);
  * hm writes HQ (16 lane-words per cycle) and HQD (16 half-words on even rows);
  * b6.c1 writes Z;
  * b6.sc writes r as lo / hi entries;
  * b6.c2 writes s and the block-7 B1.
* **Slice flags:** writer-side hits feed a pending queue that sends 1 flag per cycle into qb_act2's flag port.
  Banks are cleared at go.
* **S layout (no port conflicts by construction, asserted on every cycle):**
  * stream: address e >> 8, lane 8 ((e >> 6 & 3) ^ h(a)) + (e >> 3 & 7), h(a) = (a ^ a >> 1) & 3. The XOR swizzle
    puts the 4 px x 64 ch of a drain or hm cycle, and the 32 values of a wide step, on distinct lanes for C = 64..512.
    A model entry index maps to one physical location for every tensor shape, so the scheduler's hazards stay valid
    physically.
  * HQ on lanes 0..15, lane rotation 2 pl + (g & 1).
  * HQD and Z on lanes 16..31, rotation (pl & 3) + 8 (pl >> 2).
  * r on lanes 0..15 at addresses 64..127 and 192..255.
  * Read path: one 16:1 rotator plus a group mux in front of qb_act2's sdq. The maps use a 2:1 macro swizzle,
    f = line[0] ^ line[1], so the two chunk words of a drain cycle land in distinct macros.

## 2. Bench: PASS on both images [M]

Image (E6_s0 val i, never test), all 21 passes, stem through b7.c2. What is checked:
* the core outputs of every pass, in pass order, against `export_core` (b2; fused s / r / hq + b1; wide z / r / s + b1);
* every act item and every eot against `export_act`. This covers what the array read back from the B1 / B2 / HQ /
  HQD / Z write-back;
* every tile end against the model, cycle-exact;
* the final S (block 7's output stream) against the dataflow;
* `err` must stay 0.

| image | checked (items + output bits / words) | tiles cycle-exact | final S lane-words | errors | RTL end | model (config C + latency) | config C as is |
|---|---|---|---|---|---|---|---|
| val 0 | 633 664 | 600 / 600 | 1 024 / 1 024 | **0, PASS** | 3 748 | 3 747 | 3 622 |
| val 1 | 633 704 | 600 / 600 | 1 024 / 1 024 | **0, PASS** | 3 788 | 3 787 | 3 662 |
| val 0, DIST 2 | 633 664 | 600 / 600 | 1 024 / 1 024 | **0, PASS** | 3 775 | 3 773 | 3 622 |

RTL end is the cycle after the last macro write.

**RTL vs the model with latencies: +1 cycle, a fixed tail.** The last write of b7.c2 reaches the macro at
model de + D + 8, while the model counts de + OVH 12, so the tail is D - 3.

**RTL vs config C as is: +126 per image on both images.** That is +125 from the write-back latencies (section 3) plus
the +1 tail. With DIST 2 the gap is +153.

## 3. Cycle delta vs config C: the write-back pipeline (compile model change)

Config C treats a producer's drain end `de` (or capture) as "data written". In the RTL the data reaches the macro
later, by:
* the issue-to-core offset D (4);
* the array pipe to the shadow (4);
* the lane (FTP / WTP: 4 / 5);
* the write register.

A consumer that is RAW-bound on that data must wait. The new hook `cycles.list_schedule(..., lat=f)` (default None
leaves the schedule unchanged) adds f(producer, consumer field, consumer) to the write-done time of each hazard. The
values come from the RTL timing (`export_top.lats`, D = 4):

| producer to consumer | extra cycles | why |
|---|---|---|
| fused drain to array load (`ras`) | D + 8 = 12 | f_y at ds + D + 8 + k, then the write register |
| c1 b2 to array load | D + 7 (W 4: D + 9) | b2 at cap + D + 4, then 2 (4) line writes |
| wide drain to array load | D + 9 = 13 | w_y at ds + D + 9 + k, k <= 31 |
| hm / b6.c1 to array load | +8 on top | slice-flag queue margin; the RTL also gates the load on its flag bank being quiet (never bound on img0/1) |
| fused drain to c2 / hm drain read (`rds`, same tile / step) | D - 1 / D | asserted step-aligned |
| write after write, wide producers | 0 | |

`bub`: an hm job directly after a c2 drain waits 1 cycle, because the two share the s_rd port (r1.md deviation 6).
This costs +1.

Mean over val[:100] (E6_s0) [Mod]:

| case | cycles / image | vs config C |
|---|---|---|
| config C | 3 651.6 | 0 |
| latency, DIST 0 / **1** / 2 | 3 750.4 / **3 776.4** / 3 802.4 | +98.8 / **+124.8** / +150.8 (each DIST stage about +26) |
| only c1 b2 latency / only fused / only hm / only wide | 3 665.6 / 3 731.6 / 3 672.6 / 3 664.4 | +14 / +80 / +21 / +13 |

Per pass at DIST 1 (attributed, img mean), with the deltas taken against config C:
* b2.c2 +60
* b6.sc +26
* b7.c1 +25
* b6.hm +21
* b2.c1 +8, stem +6, b0/b1.c1 +4 each
* b6.c2 -14, b7.c2 -12 (re-attribution)

The cost is real pipeline latency at the RAW-bound c1/c2 and hm/b6 switches. The earlier config C number (3 651.7) was
optimistic by +3.4 %.

## 4. Mutants (img0, `QBT_DEFS=+define+QBT_MUT_x`): all 5 caught [M]

| mutant | fault | result |
|---|---|---|
| SWZ | stream writer drops the XOR swizzle at C = 64 | FAIL, 280 737 errors (b0.c2 s_in wrong first) |
| B2J | b2 writer swaps the two chunk lines (W 16 / 32) | FAIL, 341 864 errors (b0.c2 act items first) |
| CAP | capture / compare one cycle early | FAIL, 370 012 errors, 24 tiles off-cycle |
| ZROT | Z lane rotation by pl (collides) | FAIL, 19 048 errors (b6.c2 act items) |
| FLAG | HQD slice flags never raised | FAIL, 26 138 errors (b6.sc skips items) |

## 5. Regressions [M]

* `run_tb_core.sh`, default build: PASS on img0 / img1 (3 644 / 3 684 cycles, 0 errors).
* `run_tb_core.sh`, CREG WTP FTP PPOP BRG 2 build: PASS (same counts).
* `run_tb_act2.sh`: PASS (2 880 items, 600 / 600 tiles).
* `compile/test_compile.py --n 100`: ALL PASS with the hooks present (defaults unchanged).

## 6. Deviations from ARCH v1.2 / the brief

1. **Params bandwidth (architecture issue).** The chosen sram_sp 3904x110 delivers 1 record per cycle. One image
   needs 76 (pass, ct) sets x 64 = 4 864 records (the macro holds 3 904 rows), but an image lasts only about 3 750 cycles, so the macro
   cannot feed even a perfect set cache. qb_top therefore models params as one 64-record set per word, read
   registered: pf / pw / T2 per drain or capture. The fix needs at least 2 records per cycle plus per-(pass, ct)
   staging. This is open for R3b / R4.
2. **The descriptors are per image.** The sequencer replays the compiler's per-image config-C schedule by time.
   From block 6 on, the times depend on the image: the first descriptor that differs between img0 and img1 is at cycle
   2 095. That is the 18 L / 39 TQ / 40 CQ / 8 FQ / 24 WQ entries that differ. A data-independent sequencer (static
   commit order with event-driven RAW / shadow / lane gating) is the open R3 item. The descriptor memories are
   flop-array behavioural models (about 57 kb).
3. **r sits on lanes 0..15, not 16..31.** hm writes HQ (16 lane-words) and HQD in the same cycle, which forces HQD
   onto lanes 16..31. The b6.sc HQD reads coincide with the b6.c2 r reads, so r must avoid those lanes. With r on
   0..15 there are no read or write conflicts, asserted every cycle.
4. **Compile model edited.** `cycles.list_schedule` gained the default-off `lat` and `bub` hooks (+15 lines in an
   existing module). This follows the precedent of the supply hooks.
5. The flag port takes 1 flag per cycle, through a pending queue plus a per-bank quiet gate on int8 loads. Bit-write
   masks are assumed on rf_2p, for Z, HQD, wide s and block-7 B1. De-rotation and source muxes sit between the macro Q
   and qb_act2's rdq / sdq registers.
6. The DIST stage registers the whole act bus once, because qb_core has a single act port. Duplicating it per column
   (the 2.7 mm fan-out) is left to synthesis / P&R. DIST 2 is verified (section 2).

No synthesis of qb_top yet (R4). The head is R3b.
