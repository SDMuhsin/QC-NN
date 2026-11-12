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

