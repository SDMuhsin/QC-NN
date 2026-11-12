# QC18B-ACC: architecture spec (v1)

Accelerator for the qc18b **E6** network (CIFAR-100 QC ResNet-18, signed b = 8 QC convs, 1-bit activations, int8 image and
block 6). Golden model: `qc18b/int_bin.py` (bit-exact). Based on `qc18acc` v4 (imported, never copied). TSMC 65 nm.
Labels: [M] measured, [S] synthesis, [R] routed, [Mod] modelled, [E] estimated, [V] verified in a paper.

## Targets
* Beat Valavi JSSC'19 (1 498 GOPS/mm2 peak, conv layers, 65 nm [V]) on **executed** TOPS/mm2: ops = 2 x nonzero ternary
  terms actually executed (`qc18bacc/workload.py`: 119.9 M MAC / image E6_s0 [M]); each ternary x {1-bit, int8} MAC = 1 op.
  Report peak (array slots x f) and workload average, on routed die area (pre-route too).
* Bit-exact to `int_bin` from the integer reference to the gate-level netlist.

## Why the v4 structure changes (measurements)
* v4 PE 362 um2 per MAC/cycle, macros 1 346 [S]. A 1-bit popcount PE is 42 um2 per MAC/cycle at KB = 32 [S]
  (`results/micro.md`), so the array is no longer the cost; the **PPU** is: a requant lane is 5 659 um2 [S]
  (`results/lane.md`, multiplier 50 %, irreducible for exactness) and stage 1 has only ~127 executed MACs per output.
* Accumulators of 1-bit convs need <= 11 b, block 6 <= 18 b worst case [M].
* Block-6 int8 tensors use 4.3-4.6 nonzero bit-planes per 16 px x 8 ch word [M]; planes 6-7 are ~always zero.

## Datapath
**Array: 16 rows (output pixels) x 8 columns (8 output channels each) = 128 PEs, KB = 36.**
* Per cycle every PE consumes one *chunk*: the full 3x3 window x 32 input channels (36 bytes of 1-bit activations, 9 taps x
  4 channel groups) and the 36 QC codes of its column (same codes for all 16 rows). 73 728 MAC slots / cycle.
* 3x3 convs: chunks per tile = Cin / 32 (Cin >= 64: no idle slot). 1x1 shortcuts: one chunk = 36 channel groups of the
  centre tap (Cin 64..256 -> 8..32 groups; slots beyond Cin are zero-coded). Stem: 3 channels padded to 8 x 8 planes.
* PE = `hw/rtl/qb_pe.sv` (popcount form) with KB = 36, ACC_W = 20, plane shift + sign (two's-complement MSB plane), capture
  into a shadow register, shadow drain.
* **int8 inputs (stem, block 6) run bit-serially by plane**: a chunk item is (chunk, plane). The chunk sequence of a tile is
  ordered plane-major; a plane whose patch is all-zero is skipped (zero detect on the patch, 1 cycle look-ahead).
  Stem planes are not skipped (signed image).

**Activation supply: line buffer + fixed patch wiring (replaces v4's AGU kw window).**
* Binary maps (b1, b2, and the planes of int8 maps) live in SRAM in row-major order, one word = (pixel, 32 channels).
* A line buffer of registers holds the input rows a tile row needs (all channels): 3 rows + 1 prefetch row at W = 32/16; at
  W = 8 (tile = 2 rows) 4 + 2; at W = 4 the whole padded 6 x 6 map. Max ~12 kb.
* Patch extraction (16 pixels x 9 taps x 32 ch) is fixed wiring + a small mux per map-width / stride configuration
  (W 32, 16, 8, 4; stride 1, stride 2 = phase-split rows). Padding = zero lanes.
* SRAM read bandwidth: one input row per output tile row (512 b/cycle class).

**Weights.** 8-b block codes (129 legal states, all used [M]) decoded to the 10-b PE code by 288 decoders (8 columns x 36).
2 304 b / cycle from the weight macros, word-striped across macros; 1.395 Mb + sign(g) bits.

**PPU (drain): NL = 256 fused lanes + 512 compare units + 16 wide lanes.**
* Shadow drain: 1 024 accumulators per tile, 4 rows of PEs per cycle -> 4 cycles at 256 lanes.
* c1 of binary blocks: `b2 = acc >= T2` on compare units (512 / cycle).
* Fused lane (c2 of binary blocks, sc, stem): `qb_lane_s8` (acc x m', 3-b window shift) **plus** the residual multiply
  `rs = requant(relu(s_in), idm)` (identity blocks) in the same lane, then `s_out = sat16(y + h + rs | r)` and
  `b1_next = s_out > T1_next` (per channel). Conv-shortcut blocks: the sc pass writes r (17 b, rs reaches 45 032 [M]) into
  the stream region; c2 adds it.
* Wide lanes (`qb_lane_w`): block-6 c1 / c2 / sc, hm (relu requant of s5 into int8 planes), pool.
* The stream is updated **in place**: read s_in / r at drain, write s_out L cycles later.

**Buffers.**
* Stream S: int16 (+1 b for r), max 64 x 32 x 32 -> 1.11 Mb, banked so 256 reads + 256 writes / cycle never conflict
  (dual bank by tile parity or dual-port macros; choose by sweep).
* Binary maps: b1, b2 (64 kb each at stage 1); int8 planes of block 6 (hq 8 x 16 kb, z 8 x 8 kb); image.
* Params per output channel (T2; m', sel, h, T1_next; idm per tensor), FC int8 512 x 100 + int32 bias.

**Head.** Pool (wide lane) + FC at 64 int8 MAC/cycle, overlapped with the next image.

## Pass schedule (per block)
| pass | array input | PPU | writes |
|---|---|---|---|
| stem (8 planes) | image planes | fused (stem_m) | S, b1 of block 0 |
| binary c1 | b1 | compare (T2) | b2 |
| binary sc (stride 2) | b1 | fused, r mode | S (r) |
| binary c2 | b2 | fused (c2m + idm or + r), T1_next | S in place, b1_next |
| block 6: hm | - | wide (hm) | hq planes |
| block 6 c1 / sc / c2 | hq / hq / z planes | wide | z planes / S (r) / S, b1 of block 7 |
| head | S (relu) | wide (pool) | logits |

## Cycle / area model (scratch, to be replaced by the compiler's exact count)
KB 36, 128 PEs, NL 256, 500 MHz pre-route / 400 MHz routed, routed area = logic x 1.7 + macros x 1.15:
~3 500 cycles / image, peak ~4.0, workload-average ~1.7-1.9 executed TOPS/mm2 routed [Mod]. Risks: stream-buffer port
bandwidth, routed area factor, routed fmax.

## Milestones
1. Compiler + bit-exact dataflow model + exact cycle count (`compile/`).  2. Macro sweep (weights 2 304 b/cycle, stream
   ports, binary maps).  3. RTL + TB bit-exact.  4. Synthesis + PTPX.  5. OpenROAD P&R.  6. Results / SOTA write-up.

## v1.2 decisions (2026-11-12, measured basis in results/)
* **Golden = `golden_p2.IntBin2`** (power-of-two stream ladder; val E6 s0/s1 +0.20/+0.38 pt vs IntBin, CI low -0.58/-0.42
  [M], `results/golden_p2.md`). Identity residual = `relu(s_in) >> {0,1}` round-half-up: no multiplier.
* **Schedule v1.1** (`results/cycles.md`): stem packed 4 planes / cycle (PE group-shift mode); binary c1 `b2 = acc >= T2`
  by per-PE comparators at capture (no shadow, no lane); c1 / c2 tiles interleaved by a row-dependency list scheduler;
  b6.hm on fused lanes. 3 371 / 3 345 cycles / image at NL 256, NW 32 [Mod].
* **PPU:** 256 fused lanes `qb_lane_fn` (6 339 um2 [S], MW 28, sel 4 b, no pre-clamp) + 32 wide lanes `qb_lane_w`
  (+ ReLU / [0,127] clamp / 19-b r) for block-6 c1 / sc / c2 and pool.
* **Buffers** (`results/mem.md`, 7.07 mm2 [S]): weights rf_sp 204x144 m2 x 48 (2 304 b/cycle); stream rf_2p 256x128
  (16-b entries suffice under p2) x 32 lanes, 1R + 1W; binary maps rf_2p 128x128 x 4 per map, 3 maps (B1, B2, Z);
  params sram_sp 3904 x 110; FC 256 b/cycle (32 int8 MAC / cycle head, 1 620 cycles, overlapped); image rf_sp x 4.
* **Estimate** [E]: logic ~5.5 + macros ~7.0 = 12.5 mm2 pre-route / ~17.4 routed -> at 400 MHz routed 3.4 peak / 1.6
  average executed TOPS/mm2; pre-route at 500 MHz 5.9 / 2.85.
* **Clock is the main lever left:** floorplan-aware RTL — every macro boundary registered (as v4), weight broadcast and
  patch wiring pipelined by a register stage per PE-row group, drain/lanes placed per column.

## RTL plan
* R1 compute core `qb_core`: 128 PEs (KB 36, stem mode, comparators) + 288 code decoders + drain + 256 fused + 32 wide
  lanes; tile-level TB vs `compile/dataflow.py` vectors; synthesis (area / fmax of the core).
* R2 activation supply: line buffer + patch network (W 32/16/8/4, stride 1/2, padding, plane-major int8) + weight path.
* R3 top: buffers on macros, descriptors, list-schedule sequencer, host port, head; full-image bit-exact TB (Verilator).
* R4 synthesis + PTPX; R5 OpenROAD P&R (8-h box, explicit stop rule); R6 write-up.
