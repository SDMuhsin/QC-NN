# QC18B-ACC exact cycle count (compile/cycles.py)

Array 16 x 8 PEs, KB 36: 73728 MAC slots / cycle. Drain 1024 outputs per tile: compare units 512 (binary c1), NL fused lanes (stem, binary sc / c2), 16 wide lanes (block 6); shadow double buffering (stall when drain > next tile's compute); per-pass overhead 12 cycles; head overlapped. Plane skipping (block 6, patch = 16 px x 9 taps x 32 ch, or 16 px x 256 ch for the 1x1 sc) measured per image on val[:500] by the bit-exact dataflow model (logits == IntBin logits, torch.equal, asserted before counting). Executed MAC = nonzero ternary terms x output positions. Utilisation = executed MAC / (73728 x cycles).

## E6_s0 (/tmp/root/qc18b/exc200/E6_s0/best.pt)

Bit-exact: dataflow logits == IntBin logits on val[:500]: PASS (acc 62.00 %).

### Per pass, NL = 256 (means over images)

| pass | PPU | tiles | chunk items | plane skip | array cyc | PPU cyc | cycles | bound | exec MAC | util |
|---|---|---|---|---|---|---|---|---|---|---|
| stem | fused | 64 | 512.0 | 0.0 % | 512.0 | 256 | 528.0 | array | 405504 | 0.010 |
| b0.c1 | compare | 64 | 128.0 | 0.0 % | 128.0 | 128 | 142.0 | array | 8232960 | 0.786 |
| b0.c2 | fused | 64 | 128.0 | 0.0 % | 128.0 | 256 | 270.0 | PPU | 8323072 | 0.418 |
| b1.c1 | compare | 64 | 128.0 | 0.0 % | 128.0 | 128 | 142.0 | array | 8298496 | 0.793 |
| b1.c2 | fused | 64 | 128.0 | 0.0 % | 128.0 | 256 | 270.0 | PPU | 7757824 | 0.390 |
| b2.c1 | compare | 32 | 64.0 | 0.0 % | 64.0 | 64 | 78.0 | array | 3670016 | 0.638 |
| b2.sc | fused | 32 | 32.0 | 0.0 % | 32.0 | 128 | 141.0 | PPU | 462848 | 0.045 |
| b2.c2 | fused | 32 | 128.0 | 0.0 % | 128.0 | 128 | 144.0 | array | 6866944 | 0.647 |
| b3.c1 | compare | 32 | 128.0 | 0.0 % | 128.0 | 64 | 142.0 | array | 7911424 | 0.756 |
| b3.c2 | fused | 32 | 128.0 | 0.0 % | 128.0 | 128 | 144.0 | array | 7745536 | 0.730 |
| b4.c1 | compare | 16 | 64.0 | 0.0 % | 64.0 | 32 | 78.0 | array | 3846656 | 0.669 |
| b4.sc | fused | 16 | 16.0 | 0.0 % | 16.0 | 64 | 77.0 | PPU | 450560 | 0.079 |
| b4.c2 | fused | 16 | 128.0 | 0.0 % | 128.0 | 64 | 144.0 | array | 8086528 | 0.762 |
| b5.c1 | compare | 16 | 128.0 | 0.0 % | 128.0 | 32 | 142.0 | array | 7987712 | 0.763 |
| b5.c2 | fused | 16 | 128.0 | 0.0 % | 128.0 | 64 | 144.0 | array | 8336896 | 0.785 |
| b6.hm | wide-only | 0 | 0.0 | 0.0 % | 0.0 | 1024 | 1036.0 | PPU | 0 | 0.000 |
| b6.c1 | wide | 8 | 343.2 | 33.0 % | 343.2 | 512 | 566.9 | PPU | 4302336 | 0.103 |
| b6.sc | wide | 8 | 45.9 | 28.3 % | 45.9 | 512 | 529.7 | PPU | 479616 | 0.012 |
| b6.c2 | wide | 8 | 676.4 | 33.9 % | 676.4 | 512 | 752.4 | array | 8927104 | 0.161 |
| b7.c1 | compare | 8 | 128.0 | 0.0 % | 128.0 | 16 | 142.0 | array | 8846976 | 0.845 |
| b7.c2 | fused | 8 | 128.0 | 0.0 % | 128.0 | 32 | 144.0 | array | 8934016 | 0.841 |
| **image** | | 600 | 3289.5 | | 3289.5 | 4400 | **5757.1** | | 119873024 | **0.282** |

Most expensive passes (NL 256): b6.hm 1036 (PPU-bound), b6.c2 752 (array-bound), b6.c1 567 (PPU-bound)

### NL sweep (fused lanes; compare units 512, wide lanes 16)

| NL | cycles / image (mean) | min | max | utilisation | images/s at 500 MHz |
|---|---|---|---|---|---|
| 64 | 9429.1 | 9292 | 9526 | 0.172 | 53027 |
| 128 | 6733.1 | 6596 | 6830 | 0.241 | 74260 |
| 192 | 6245.1 | 6108 | 6342 | 0.260 | 80063 |
| 256 | 5757.1 | 5620 | 5854 | 0.282 | 86850 |
| 384 | 5575.1 | 5438 | 5672 | 0.292 | 89685 |

### Wide-lane count sensitivity (NL 256; spec NW = 16)

| NW | cycles / image | block-6 cycles | utilisation |
|---|---|---|---|
| 16 | 5757.1 | 2885.1 | 0.282 |
| 32 | 4777.4 | 1905.4 | 0.340 |
| 64 | 4361.4 | 1489.4 | 0.373 |
| 128 | 4153.4 | 1281.4 | 0.391 |

Plane-skip ratio (skipped (chunk, plane) items / all 8-plane items): b6.c1 33.0 %, b6.sc 28.3 %, b6.c2 33.9 %

## E6_s1 (/tmp/root/qc18b/exc200/E6_s1/best.pt)

Bit-exact: dataflow logits == IntBin logits on val[:500]: PASS (acc 61.40 %).

### Per pass, NL = 256 (means over images)

| pass | PPU | tiles | chunk items | plane skip | array cyc | PPU cyc | cycles | bound | exec MAC | util |
|---|---|---|---|---|---|---|---|---|---|---|
| stem | fused | 64 | 512.0 | 0.0 % | 512.0 | 256 | 528.0 | array | 430080 | 0.011 |
| b0.c1 | compare | 64 | 128.0 | 0.0 % | 128.0 | 128 | 142.0 | array | 8667136 | 0.828 |
| b0.c2 | fused | 64 | 128.0 | 0.0 % | 128.0 | 256 | 270.0 | PPU | 8609792 | 0.433 |
| b1.c1 | compare | 64 | 128.0 | 0.0 % | 128.0 | 128 | 142.0 | array | 8306688 | 0.793 |
| b1.c2 | fused | 64 | 128.0 | 0.0 % | 128.0 | 256 | 270.0 | PPU | 8241152 | 0.414 |
| b2.c1 | compare | 32 | 64.0 | 0.0 % | 64.0 | 64 | 78.0 | array | 3612672 | 0.628 |
| b2.sc | fused | 32 | 32.0 | 0.0 % | 32.0 | 128 | 141.0 | PPU | 471040 | 0.045 |
| b2.c2 | fused | 32 | 128.0 | 0.0 % | 128.0 | 128 | 144.0 | array | 7772160 | 0.732 |
| b3.c1 | compare | 32 | 128.0 | 0.0 % | 128.0 | 64 | 142.0 | array | 7731200 | 0.738 |
| b3.c2 | fused | 32 | 128.0 | 0.0 % | 128.0 | 128 | 144.0 | array | 7862272 | 0.741 |
| b4.c1 | compare | 16 | 64.0 | 0.0 % | 64.0 | 32 | 78.0 | array | 3787264 | 0.659 |
| b4.sc | fused | 16 | 16.0 | 0.0 % | 16.0 | 64 | 77.0 | PPU | 442368 | 0.078 |
| b4.c2 | fused | 16 | 128.0 | 0.0 % | 128.0 | 64 | 144.0 | array | 8151552 | 0.768 |
| b5.c1 | compare | 16 | 128.0 | 0.0 % | 128.0 | 32 | 142.0 | array | 8075776 | 0.771 |
| b5.c2 | fused | 16 | 128.0 | 0.0 % | 128.0 | 64 | 144.0 | array | 8499200 | 0.801 |
| b6.hm | wide-only | 0 | 0.0 | 0.0 % | 0.0 | 1024 | 1036.0 | PPU | 0 | 0.000 |
| b6.c1 | wide | 8 | 374.6 | 26.8 % | 374.6 | 512 | 570.8 | PPU | 4308352 | 0.102 |
| b6.sc | wide | 8 | 48.9 | 23.6 % | 48.9 | 512 | 530.1 | PPU | 480512 | 0.012 |
| b6.c2 | wide | 8 | 620.8 | 39.4 % | 620.8 | 512 | 696.8 | array | 8935552 | 0.174 |
| b7.c1 | compare | 8 | 128.0 | 0.0 % | 128.0 | 16 | 142.0 | array | 8879616 | 0.848 |
| b7.c2 | fused | 8 | 128.0 | 0.0 % | 128.0 | 32 | 144.0 | array | 8958080 | 0.844 |
| **image** | | 600 | 3268.3 | | 3268.3 | 4400 | **5705.8** | | 122222464 | **0.291** |

Most expensive passes (NL 256): b6.hm 1036 (PPU-bound), b6.c2 697 (array-bound), b6.c1 571 (PPU-bound)

### NL sweep (fused lanes; compare units 512, wide lanes 16)

| NL | cycles / image (mean) | min | max | utilisation | images/s at 500 MHz |
|---|---|---|---|---|---|
| 64 | 9377.8 | 9265 | 9473 | 0.177 | 53318 |
| 128 | 6681.8 | 6569 | 6777 | 0.248 | 74830 |
| 192 | 6193.8 | 6081 | 6289 | 0.268 | 80726 |
| 256 | 5705.8 | 5593 | 5801 | 0.291 | 87631 |
| 384 | 5523.8 | 5411 | 5619 | 0.300 | 90518 |

### Wide-lane count sensitivity (NL 256; spec NW = 16)

| NW | cycles / image | block-6 cycles | utilisation |
|---|---|---|---|
| 16 | 5705.8 | 2833.8 | 0.291 |
| 32 | 4753.6 | 1881.5 | 0.349 |
| 64 | 4337.6 | 1465.5 | 0.382 |
| 128 | 4129.6 | 1257.5 | 0.401 |

Plane-skip ratio (skipped (chunk, plane) items / all 8-plane items): b6.c1 26.8 %, b6.sc 23.6 %, b6.c2 39.4 %

## Spec deviations / findings (compile/program.py, dataflow.py)

1. sign(g): the integer weight sign(g) M is not QC per block, so the PE accumulates M x and the PPU input negates per output channel (acc' = sgn acc, 1 b / channel, already counted in ARCH's '+ sign(g) bits').
2. Bias pre-add: IntBin adds the int32 BN bias BEFORE the requant for the stem (stem_b) and block 6 (c1b / scb / c2b); the lane export's stem domain includes it. The PPU needs a per-channel adder in front of the multiplier for these passes (qb_lane_s8 / qb_lane_w only add h after the product).
3. qb_lane_w needs an output clamp to [0, 127] (hm, block-6 c1, pool) and input ReLU (hm, pool); qb_lane only saturates to +-32767.
4. Block-6 sc r reaches 209 625 worst case (19 b; ARCH: r 17 b, 45 032 was the idm worst case). Exact solution used: r stored as two S entries (lo 16 b, hi signed; 8192 x 2 entries), qb_lane_w r port 19 b and y clamp 19 b instead of 18 b (sat16(clamp(y) + r) == sat16(y + r) needs 2^18 - 1 >= 32767 + max|r|). Binary blocks: r <= 40 160 / 45 032 (17 b), qb_lane_s8 r port 16 -> 17 b (its 19-b sum holds: |y + h + r| <= 162 004).
5. Fused-lane idm: rs = window requant of relu(s_in) with the export's per-tensor (m', sel) = a second 16 x 29 multiplier per fused lane (only identity-block c2 passes use it).
6. Block 6 dominates: at NW = 16 wide lanes hm is a 1 024-cycle PPU-only pass and c1 / sc are PPU-bound (64 drain cycles per tile); ARCH's ~3 500 cycles / image is not reached with 16 wide lanes (see NW table).
7. NL > 256 needs more than the 256 + 256 stream-buffer ports / cycle that ARCH sizes S for.
8. Line buffer (estimate, not modelled): stride-2 passes b4.c1 / b4.sc and block-6 c1 / sc need up to 18 kb per plane (ARCH: ~12 kb).
9. Stem: 3 channels -> 1 group per tap, 9 of 36 bytes per chunk, 8 unskipped planes: 512 array cycles at 1 % utilisation (the PE's single per-cycle plane shift prevents packing planes into the idle groups).

Observed max |r| over all seeds and val images run (worst case: program checks): b0.c2.idm 34299, b1.c2.idm 24307, b2.sc 21095, b3.c2.idm 38365, b4.sc 12207, b5.c2.idm 25069, b6.sc 10193, b7.c2.idm 30446

## v1.1 (compile/*.py --v 11, default; --v 1 reproduces the v1 sections above)

Changes (each selectable in cycles.CONFIGS; the program / dataflow default is --v 11, --v 1 reproduces v1):

1. Fused lane v1.1 (program.lane_f): per-channel bias pre-add before the multiplier, input-ReLU mode, output clamp [0, 127] mode and a per-channel input pre-clamp x -> clamp(x, lo_c, hi_c). requant is monotone (m0 >= 0), so with the output observed only through clamp(., A_c, B_c) (u8: [0, 127]; r / c2: the int16 saturation of the sum it enters, A/B from the worst-case range of the other operand) lo_c = max{x: rq(x) <= A_c}, hi_c = min{x: rq(x) >= B_c} change no output; asserted exhaustively on every integer of every channel's worst-case domain (before the pre-clamp). A block-6 pass moves to the NL fused lanes iff every channel fits: 16-b signed input after the pre-clamp, an exact multiplier of <= 30 b in the lane's shift window s' = 17 + sel, sel < 8 (qb_lane_s8), and the lane's internal widths (18-b y, 17-b r, 19-b sum). MW needed per pass and the reason a pass stays on the wide lanes are listed per checkpoint below.
2. Stem packing (dataflow.pe_stem_packed): the 36 bytes are 9 taps x 4 channel groups; in stem mode group g of cycle h carries plane 4h + g of the 8-padded image channels (same 9 tap codes in every group), the PE popcounts the 4 groups separately and adds sum_g (u_g - nneg_g) << g, shifted by 4h, plane 7 (group 3 of h = 1) negative. 2 cycles per stem tile instead of 8 (bit-exact, ACC_W wrap checked).
3. Binary c1: b2 = acc' >= T2 by 1024 per-PE comparators at capture (no shadow, no lanes; b2 written at capture), and an event-driven list scheduler over tiles (cycles.list_schedule): array one tile at a time; shadow one per PE (a drained tile starts just in time to capture when the shadow frees, so the array is not held); fused lanes NL outputs / cycle and wide lanes 16 / cycle shared FIFO by drains and PPU-only jobs (hm in 1024-output jobs); candidates = head tile of each of the first 4 unfinished passes whose hazards are all scheduled, earliest feasible start wins, ties in program order. Hazards (cycles.tiles_of, 64-entry blocks): RAW row-granular (every input row of the tile's patch incl. halo / stride / phase, all channels, all planes, counts as written when the producing tile's drain completes; drain-time reads of s_in / r likewise), WAR (a write may start only after every earlier-ordered reader of the old value has finished reading it; this covers the in-place stream: the sc pass's r overwrites s_in rows, block-6 sc's r hi entries overwrite s6 rows that hm has not read yet, and every re-used B1 / B2 / HQ / Z row), WAW. OVH = 12 cycles only where the array idles at a pass boundary (start = data ready + 12) and once at the end of the image. Per-pass cycles in the schedule are attributed (array compute -> own pass, array idle -> pass of the binding hazard or of the shadow holder, tail -> last drain) and sum to the image cycles.

### E6_s0 (/tmp/root/qc18b/exc200/E6_s0/best.pt)

Bit-exact (v1.1 program: packed stem, fused-lane block 6 where it fits): dataflow logits == IntBin logits on val[:500]: PASS (acc 62.00 %).

* v1.1 fused fit b6.hm: domain [-32767, 32767] (16 b, pre-add of a 1-b bias), pre-clamped [129, 32638] (16 b), MW needed 15: MOVED to the fused lanes (MW 29); exact on every integer of every channel's worst-case domain (16776960 values): PASS; output range [0, 127]
* v1.1 fused fit b6.c1: domain [-43804, 39836] (17 b, pre-add of a 13-b bias), pre-clamped [2, 38643] (17 b), MW needed 99: stays on the wide lanes (pre-clamped input 17 b > 16 b; MW 99 > 30; with a 4-b sel window [17, 32]: MW 22, s' used [17, 30]; with a 5-b sel window [17, 40]: MW 22, s' used [17, 30]; 7 of 512 channels need > 16 b after the pre-clamp)
* v1.1 fused fit b6.sc: domain [-15712, 5135] (15 b, pre-add of a 15-b bias), pre-clamped [-15712, 5135] (15 b), MW needed 99: stays on the wide lanes (MW 99 > 30; with a 4-b sel window [17, 32]: MW 30, s' used [17, 26]; with a 5-b sel window [17, 40]: MW 30, s' used [17, 26]; |r| reaches 209625 after the pre-clamp (fused lane: r 17 b, y 18 b))
* v1.1 fused fit b6.c2: domain [-339542, 85991] (20 b, pre-add of a 20-b bias), pre-clamped [-339542, 85991] (20 b), MW needed 99: stays on the wide lanes (pre-clamped input 20 b > 16 b; MW 99 > 30; with a 4-b sel window [17, 32]: MW 99, s' used [17, 32]; with a 5-b sel window [17, 40]: MW 31, s' used [17, 33]; 15 of 512 channels need > 16 b after the pre-clamp)

Schedule check (changes 3 / all, every NL, every image): 6888 hazard pairs (RAW row-granular incl. halo / stride / phase, WAR incl. the in-place stream, WAW; 64-entry blocks) hold on the scheduled times: every read sees exactly its program-order producer's data, so the dataflow values (logits == IntBin) are unchanged in the scheduled order: PASS.

Value replay (dataflow.replay): val[:20] executed tile by tile in the NL-256 scheduled order (events by time; each tile computed from snapshots of exactly its footprint rows taken at its read times, only its own outputs written at its write time) gives logits == IntBin (torch.equal): PASS. (Sensitivity: dropping the WAR or the drain-read RAW hazards from the scheduler makes both the hazard check and the replay fail; compile/test_compile.py.)

#### Cycles / image (mean over val[:500]) and the contribution of each change

| config | NL 128 | NL 192 | NL 256 | NL 384 | util NL 256 |
|---|---|---|---|---|---|
| v1 | 6733.1 | 6245.1 | 5757.1 | 5575.1 | 0.282 |
| 1 only | 5837.1 | 5307.1 | 4797.1 | 4594.1 | 0.339 |
| 2 only | 6727.1 | 6113.1 | 5499.1 | 5254.1 | 0.296 |
| 3 only | 5903.4 | 5507.4 | 5035.4 | 4985.4 | 0.323 |
| all (v1.1) | 4989.4 | 4435.4 | 3805.3 | 3736.3 | 0.427 |

#### v1.1 per pass, NL = 256 (attributed cycles: array compute -> own pass, array idle -> pass of the binding hazard, shadow stall -> pass holding the shadow, tail -> last drain; sums to the image)

| pass | PPU | tiles | chunk items | array cyc | PPU cyc | attributed cyc | exec MAC |
|---|---|---|---|---|---|---|---|
| stem | fused | 64 | 128.0 | 128.0 | 256 | 136.0 | 405504 |
| b0.c1 | pecmp | 64 | 128.0 | 128.0 | 0 | 128.0 | 8232960 |
| b0.c2 | fused | 64 | 128.0 | 128.0 | 256 | 134.0 | 8323072 |
| b1.c1 | pecmp | 64 | 128.0 | 128.0 | 0 | 128.0 | 8298496 |
| b1.c2 | fused | 64 | 128.0 | 128.0 | 256 | 195.0 | 7757824 |
| b2.c1 | pecmp | 32 | 64.0 | 64.0 | 0 | 64.0 | 3670016 |
| b2.sc | fused | 32 | 32.0 | 32.0 | 128 | 32.0 | 462848 |
| b2.c2 | fused | 32 | 128.0 | 128.0 | 128 | 137.0 | 6866944 |
| b3.c1 | pecmp | 32 | 128.0 | 128.0 | 0 | 128.0 | 7911424 |
| b3.c2 | fused | 32 | 128.0 | 128.0 | 128 | 128.0 | 7745536 |
| b4.c1 | pecmp | 16 | 64.0 | 64.0 | 0 | 64.0 | 3846656 |
| b4.sc | fused | 16 | 16.0 | 16.0 | 64 | 25.0 | 450560 |
| b4.c2 | fused | 16 | 128.0 | 128.0 | 64 | 143.0 | 8086528 |
| b5.c1 | pecmp | 16 | 128.0 | 128.0 | 0 | 128.0 | 7987712 |
| b5.c2 | fused | 16 | 128.0 | 128.0 | 64 | 128.0 | 8336896 |
| b6.hm | fused | 0 | 0.0 | 0.0 | 64 | 80.0 | 0 |
| b6.c1 | wide | 8 | 343.2 | 343.2 | 512 | 549.2 | 4302336 |
| b6.sc | wide | 8 | 45.9 | 45.9 | 512 | 45.9 | 479616 |
| b6.c2 | wide | 8 | 676.4 | 676.4 | 512 | 1160.3 | 8927104 |
| b7.c1 | pecmp | 8 | 128.0 | 128.0 | 0 | 128.0 | 8846976 |
| b7.c2 | fused | 8 | 128.0 | 128.0 | 32 | 144.0 | 8934016 |
| **image** | | | | 2905.5 | | **3805.3** (min 3669, max 3901) | 119873024 |

Top-3 passes (NL 256, attributed): b6.c2 1160, b6.c1 549, b1.c2 195

### E6_s1 (/tmp/root/qc18b/exc200/E6_s1/best.pt)

Bit-exact (v1.1 program: packed stem, fused-lane block 6 where it fits): dataflow logits == IntBin logits on val[:500]: PASS (acc 61.40 %).

* v1.1 fused fit b6.hm: domain [-32767, 32767] (16 b, pre-add of a 1-b bias), pre-clamped [129, 32638] (16 b), MW needed 15: MOVED to the fused lanes (MW 29); exact on every integer of every channel's worst-case domain (16776960 values): PASS; output range [0, 127]
* v1.1 fused fit b6.c1: domain [-43621, 40386] (17 b, pre-add of a 12-b bias), pre-clamped [4, 39580] (17 b), MW needed 99: stays on the wide lanes (pre-clamped input 17 b > 16 b; MW 99 > 30; with a 4-b sel window [17, 32]: MW 23, s' used [17, 31]; with a 5-b sel window [17, 40]: MW 23, s' used [17, 31]; 15 of 512 channels need > 16 b after the pre-clamp)
* v1.1 fused fit b6.sc: domain [-33960, 5689] (17 b, pre-add of a 16-b bias), pre-clamped [-33960, 5689] (17 b), MW needed 99: stays on the wide lanes (pre-clamped input 17 b > 16 b; MW 99 > 30; with a 4-b sel window [17, 32]: MW 30, s' used [17, 28]; with a 5-b sel window [17, 40]: MW 30, s' used [17, 28]; |r| reaches 162624 after the pre-clamp (fused lane: r 17 b, y 18 b); 1 of 512 channels need > 16 b after the pre-clamp)
* v1.1 fused fit b6.c2: domain [-86829, 84654] (18 b, pre-add of a 13-b bias), pre-clamped [-85297, 73947] (18 b), MW needed 99: stays on the wide lanes (pre-clamped input 18 b > 16 b; MW 99 > 30; with a 4-b sel window [17, 32]: MW 31, s' used [17, 31]; with a 5-b sel window [17, 40]: MW 31, s' used [17, 31]; 10 of 512 channels need > 16 b after the pre-clamp)

Schedule check (changes 3 / all, every NL, every image): 6888 hazard pairs (RAW row-granular incl. halo / stride / phase, WAR incl. the in-place stream, WAW; 64-entry blocks) hold on the scheduled times: every read sees exactly its program-order producer's data, so the dataflow values (logits == IntBin) are unchanged in the scheduled order: PASS.

Value replay (dataflow.replay): val[:20] executed tile by tile in the NL-256 scheduled order (events by time; each tile computed from snapshots of exactly its footprint rows taken at its read times, only its own outputs written at its write time) gives logits == IntBin (torch.equal): PASS. (Sensitivity: dropping the WAR or the drain-read RAW hazards from the scheduler makes both the hazard check and the replay fail; compile/test_compile.py.)

#### Cycles / image (mean over val[:500]) and the contribution of each change

| config | NL 128 | NL 192 | NL 256 | NL 384 | util NL 256 |
|---|---|---|---|---|---|
| v1 | 6681.8 | 6193.8 | 5705.8 | 5523.8 | 0.291 |
| 1 only | 5785.8 | 5255.8 | 4745.8 | 4542.8 | 0.349 |
| 2 only | 6675.8 | 6061.8 | 5447.8 | 5202.8 | 0.304 |
| 3 only | 5851.7 | 5455.7 | 4983.7 | 4933.7 | 0.333 |
| all (v1.1) | 4937.7 | 4383.7 | 3753.7 | 3684.7 | 0.442 |

#### v1.1 per pass, NL = 256 (attributed cycles: array compute -> own pass, array idle -> pass of the binding hazard, shadow stall -> pass holding the shadow, tail -> last drain; sums to the image)

| pass | PPU | tiles | chunk items | array cyc | PPU cyc | attributed cyc | exec MAC |
|---|---|---|---|---|---|---|---|
| stem | fused | 64 | 128.0 | 128.0 | 256 | 136.0 | 430080 |
| b0.c1 | pecmp | 64 | 128.0 | 128.0 | 0 | 128.0 | 8667136 |
| b0.c2 | fused | 64 | 128.0 | 128.0 | 256 | 134.0 | 8609792 |
| b1.c1 | pecmp | 64 | 128.0 | 128.0 | 0 | 128.0 | 8306688 |
| b1.c2 | fused | 64 | 128.0 | 128.0 | 256 | 195.0 | 8241152 |
| b2.c1 | pecmp | 32 | 64.0 | 64.0 | 0 | 64.0 | 3612672 |
| b2.sc | fused | 32 | 32.0 | 32.0 | 128 | 32.0 | 471040 |
| b2.c2 | fused | 32 | 128.0 | 128.0 | 128 | 137.0 | 7772160 |
| b3.c1 | pecmp | 32 | 128.0 | 128.0 | 0 | 128.0 | 7731200 |
| b3.c2 | fused | 32 | 128.0 | 128.0 | 128 | 128.0 | 7862272 |
| b4.c1 | pecmp | 16 | 64.0 | 64.0 | 0 | 64.0 | 3787264 |
| b4.sc | fused | 16 | 16.0 | 16.0 | 64 | 25.0 | 442368 |
| b4.c2 | fused | 16 | 128.0 | 128.0 | 64 | 143.0 | 8151552 |
| b5.c1 | pecmp | 16 | 128.0 | 128.0 | 0 | 128.0 | 8075776 |
| b5.c2 | fused | 16 | 128.0 | 128.0 | 64 | 128.0 | 8499200 |
| b6.hm | fused | 0 | 0.0 | 0.0 | 64 | 80.0 | 0 |
| b6.c1 | wide | 8 | 374.6 | 374.6 | 512 | 552.7 | 4308352 |
| b6.sc | wide | 8 | 48.9 | 48.9 | 512 | 48.9 | 480512 |
| b6.c2 | wide | 8 | 620.8 | 620.8 | 512 | 1102.1 | 8935552 |
| b7.c1 | pecmp | 8 | 128.0 | 128.0 | 0 | 128.0 | 8879616 |
| b7.c2 | fused | 8 | 128.0 | 128.0 | 32 | 144.0 | 8958080 |
| **image** | | | | 2884.3 | | **3753.7** (min 3641, max 3848) | 122222464 |

Top-3 passes (NL 256, attributed): b6.c2 1102, b6.c1 553, b1.c2 195

### v1.1 findings / deviations

1. Change 1 moves only b6.hm (both seeds): MW needed 15 (the lane keeps MW 29), input ReLU + pre-clamp [129, 32638] + u8 clamp. b6.c1 / sc / c2 stay on the wide lanes: none has an exact multiplier inside qb_lane_s8's shift window s' in [17, 24] (they need s' up to 26-31, i.e. a 4-b sel; there MW 22-23 for c1, 30 for sc, 31 for c2), c1 / c2 (and s1's sc) need > 16-b inputs after the pre-clamp in 7-15 channels, and sc's r reaches 209 625 / 162 624 (fused lane: 17-b r, 18-b y). No moved pass uses the bias pre-add (hm has no bias); it remains needed for the stem.
2. Block 6 is now ~half of the image (s0: hm 80 + c1 549 + sc 46 + c2 1160 of 3805 attributed cycles): c1 / sc / c2 drains are 3 x 8 x 64 = 1536 serial wide-lane cycles at NW 16. Next levers: NW 32, or a fused-lane mode with 4-b sel and 17-b input for b6.c1.
3. Change 2 hardware (not synthesized): the PE popcount split into 4 group sub-sums (9 bytes each) + a shift-add sum_g (u_g - nneg_g) << g with group 3 subtracted for plane 7, and the plane shift 4h; binary mode adds the 4 sub-sums unshifted.
4. Change 3 hardware: 1024 comparators (20-b acc' vs the column's 16-b T2, sign(g) folded), B2 written at capture (1024 b per tile; binary c1 tiles take >= 2 cycles, so a 512-b port + one tile of buffering suffices). The interleaved schedule keeps two passes live (c1 of block i+1 and c2 of block i): two line-buffer contexts (2 x the ARCH line buffer) and per-tile switching of weight-code / parameter streams.
5. The WAR hazards are binding, not theoretical: without them the schedule clobbers stream / B1 / B2 rows (hazard check and value replay both fail). Modelled in-place cases: binary sc r over s_in rows, block-6 sc r-hi entries over s6 rows hm has not read yet, B1 / B2 rows re-used by the next block.
6. The three changes are close to additive at NL 256 (s0: -960 / -258 / -722 alone, -1952 together). With interleaving the fused lanes stop being the bottleneck above NL 256 (NL 384 gains ~70 cycles); NL 128 costs ~1180 cycles (stage-1 c2 / stem drains).

