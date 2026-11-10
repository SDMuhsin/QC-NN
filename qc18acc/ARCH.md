# QC18-ACC: architecture spec (v2; v3 = last section)

v2 = v1 (git tag `qc18acc-v1`, results in `results/power.md`) + the kw sliding window (tap order kh, cb, kw; section
"kw window") + gated macro clocks (implementation, `hw/tech/qa_sram_tech.sv`) + PE function sub-instances.
Results of v2: `results/power_v2.md`.

Target network: `qc18` model **s8kd** (signed, b = 8, distilled; int8 test 91.33 / 91.20 % for seeds 0 / 1; this design uses seed 0),
integer-exact reference `qc18/int8.py` (`IntNet`). Every conv GEMM matrix `M[cout, (kh, kw, cin)]` consists of
8x8 blocks `B = sum_s c[s] P_s` (`qc.structure`, `P_s[i, j] = 1 iff j = (i + s) mod 8`), with at most two
nonzero `c[s]` in {-1, +1}. The int8 conv weight is `d_c M` with `d_c = sign(s_c)` per output channel.

## Why a dedicated engine and not the QC-GeMMX cluster (`qcacc/`)

* `qcacc/RESULTS.md` section 4: in the GeMMX cluster, 75 % of the cycles and 76 % of the image energy go to residual
  adds, pooling and setup on the Snitch cores. The QC array gain (x0.55 conv energy) shrank to x0.81 per image.
* ResNet-18 (11.2 M weights) does not fit the 256 KiB TCDM as int8. As b = 8 QC codes it is 218 KB. The cluster
  would need to stream weights from the memory island anyway.
* At b = 8 a block has 2 nonzero shifts out of 8. A QC block-PE needs 2 rotations and 8 adders, where a ternary tile
  needs 56 adds. GeMMX's 8x8x8 K-reduction tile cannot use this sparsity.

Reused by import: `qc18` (model, `IntNet`, `decompose`), `qc.structure`, `flow/tsmc65` (DC, PT, SRAM compiler,
VCS, OpenROAD), and the power / energy method and scripts of `qcacc/gls` + `nn/gls`.

## Top level

```
 host port (32-bit write/read, memory-mapped) --> config regs, descriptor RAM, weight / param / act memories
                                                   |
  sequencer (layer descriptors) --> AGU --> act buffers A/B/C (8 banks x 64 b each) --8 words--> [8 x 8 PE array]
                                     \--> weight code SRAM (80 b/word) -----------8 codes------>      |
                                                                                       shadow chains (drain)
                                          PPU (8 lanes: bias, sign, requant, residual, clamp) <-------/
                                          head (pool + FC)  -> logits[10] int32
```

## Data formats

* **Activation word**: 64 b = 8 channels (int8, lane i = channel 8*cb + i) of one pixel. Stored maps are int8
  in [0, 127], except the input image (int8 [-127, 127], 3 channels + 5 zero channels = 1 plane).
* **Map layout** (per tensor; chosen by the compiler from the stride of the tensor's array consumer):
  `index(cb, y, x) = cb * H * W + pix(y, x)` with
  * raster: `pix = y * W + x` (consumers with stride 1);
  * phase:  `pix = ((y & 1) * 2 + (x & 1)) * (H/2) * (W/2) + (y >> 1) * (W/2) + (x >> 1)` (stride 2).
  Bank = `index mod 8` and address in bank = `index >> 3`, plus a per-tensor base.
  For output tile pixels `o0..o0+7` (8-aligned raster output index) and a tap (kh, kw), the input indexes are
  `o_i + c(kh, kw)` in both layouts. That gives 8 consecutive indexes, so 8 distinct banks: no conflicts at
  W = 4..32 and stride 1 or 2. Lanes whose input coordinate is outside the map read zero (padding).
* **Residual R** (conv-shortcut output, requantised to the block-output scale, NOT clamped): int16, stored as two
  int8 planes per channel group (low byte at plane `2 cb`, high byte at `2 cb + 1`, same layout rules). The
  compiler proves `|R| < 2^15` per layer from the worst-case accumulator bound.
* **Weight code**: 10 b per 8x8 block = two terms `(k[2:0], t[1:0])`, with trit `t`: 00 = 0, 01 = +1, 11 = -1.
  Term order is canonical: ascending shift, and a zero term is `(0, 00)`. Block output:
  `y[i] = t1 * x[(i + k1) mod 8] + t2 * x[(i + k2) mod 8]`.
  The weight word is 80 b: the codes of 8 output groups (64 output channels, column g = channel group g) for
  one (kh, kw, cb). Words are ordered per pass as `og` (64-channel group), then kh, cb, kw (v2; v1: kh, kw, cb),
  which is the order the array consumes them.  The kw sequence is 0, 1, 2, except stride-2 3x3 passes: 0, 2, 1.
* **Channel params** (per conv output channel, 72-b word): `bias` int32, `m0` 31 b (unsigned), `sh` 6 b, `d` 1 b
  (1 = negate the accumulator), 2 b spare.

## PE array: 8 rows (pixels p) x 8 columns (output groups g)

* Row p receives the activation word of tile pixel `o0 + p` for the current (kh, kw, cb). It is zero if padded.
  The words come through the kw window (below).
* Column g receives the code of block (og*8 + g, kh, kw, cb).
* PE(p, g): two 8-lane rotators (3-stage log shifter, 8-b lanes), trit apply (negate / zero, 9 b), 8 adders,
  8 accumulators of 20 b. v2 RTL: sub-instances `u_rot1`, `u_rot2` (rotators), `u_tadd` (trits + 2-term add,
  10 b), `u_acc` (accumulate add, 20 b); v1 had one 3-input add per lane in a flat PE. The worst case is 2 * 576 * 127 < 2^18, and the compiler asserts the bound per layer.
* Output-stationary. A tile (8 pixels x 64 channels) accumulates over `K = kh*kw*Cin/8` cycles, one block per
  PE per cycle (stem: Cin padded to 8, K = 9). At the end of a tile the accumulators move to a shadow register
  in 1 cycle and the next tile starts.
* Drain: the shadows of column g form a chain along p. The PPU takes one word (8 lanes = 8 channels of one pixel)
  per cycle in the order `p` outer, `g` inner, and each column chain shifts once per 8 cycles. A tile drain takes 64
  cycles. If the next tile ends before the drain is done, the array stalls (stem K = 9, 1x1 shortcuts K = 8..32).
* Pipeline: the AGU + SRAM read and the code read are aligned to the same cycle. Register stages are free, and
  are documented in the RTL.

## kw window (v2)

Per tile the taps run kh (outer), cb, kw (inner). For a tap with base index `B = o0 + c(kh, kw, cb)` lane p reads
index `B + p`. In a kw run the next tap has `B' = B + 1` in both layouts: stride 1 raster, kw -> kw + 1 adds 1;
stride 2 phase (pad 1), kw = 0 and kw = 2 read the same odd-x phase plane at x offsets `ex >> 1` = -1 and 0, so the
stride-2 run visits kw 0, 2, 1 and the step 0 -> 2 is a shift (2 -> 1 changes plane). Hardware:

* the S3 window `W[0..7]` holds raw 64-b words, slot j = index `B + j` (bank `(B + j) mod 8`), never masked;
* a SHIFT step (structural: kw index 1 or 2 of a stride-1 run, kw index 1 of a stride-2 run; the RTL checks in
  simulation that it is exactly `B == B_prev + 1`) moves slot j + 1 to slot j;
* the AGU keeps `have[j]` = slot j holds its word: `held = shift ? have >> 1 : 0`, `rd = lane & ~held`,
  `have <= held | lane`; only the `rd` banks are read (one bank per shift step, except at the row wrap of 4-wide
  maps where a lane that was padding becomes valid; the valid lanes on the first step of a run);
* row p = `lane[p] ? W[p] : 0`: the per-tap padding mask (registered) is applied at the array input, so an
  out-of-map word that sits in the window never reaches a PE; padding slots are never read.

Array act-bank reads per image (s8kd, counter `CSR_ACT_RD` = model `layout.act_reads`): 409 572 vs 946 644 in v1
(one per valid lane), x0.433. Cycles are unchanged (159 982 / image).

## PPU (8 lanes, one output word per cycle)

Per lane, channel c (params from a 64-entry register file, loaded at each `og` change from the param SRAM):
```
v   = (d ? -acc : acc) + bias                       // int32 (the compiler asserts no overflow)
y   = (v * m0 + 2^(sh-1)) >>> sh                    // 64-bit product, arithmetic shift  == int8.requant
mode RELU  : out = clamp(y, 0, 127)                                       -> int8 map
mode RAW16 : out = y   (int16, asserted)                                  -> R planes
mode RES_ID: out = clamp(y + ((q * idm0 + 2^(idsh-1)) >>> idsh), 0, 127)  q = int8 block input at the same pixel/channel
mode RES_R : out = clamp(y + R, 0, 127)                                    R = int16 from the R planes
```
`idm0` / `idsh` are per-pass (per-tensor) constants. Residual operands come from a buffer other than the one the
pass writes; RES_R reads 2 words per output word, so it takes 2 cycles per word.

## Buffers and pass schedule (3 activation buffers A, B, C, each 8 banks x 1024 x 64 b = 64 KiB)

| pass | array reads | PPU reads | writes | mode |
|---|---|---|---|---|
| stem | image (buffer C, raster) | - | A | RELU |
| block, identity: c1 | X | - | Y | RELU |
| block, identity: c2 | Y | X (q) | Z | RES_ID |
| block, conv sc: c1 (stride 2) | X (phase) | - | Y | RELU |
| block, conv sc: sc (1x1, stride 2) | X (phase) | - | Z (R planes) | RAW16 |
| block, conv sc: c2 | Y | Z (R) | X | RES_R |

X / Y / Z rotate over A / B / C. The compiler assigns buffers and bases and proves every tensor fits. The largest
are 64x32x32 int8 = 64 KiB and R 128x16x16 int16 = 64 KiB.

## Head (pool + FC)

The final map is 512 ch x 4 x 4. For each cb (64 of them): sum the 16 pixel words per lane (int32), requant with the
per-tensor pool multiplier, and clamp [0, 127] to get `p[8]`. Then `logit[j] += sum_lane W8[j, 8cb + lane] p[lane]`
for j = 0..9, with 8 int8 x uint7 multipliers and 10 int32 accumulators. The FC weights (5120 B) and biases are in the
param SRAM. The output is the 10 int32 accumulators + bias, exactly `igemm(F.linear, p, fW8) + fbq` of `IntNet`.
The host does the float dequant (`* fscale`) and the argmax. The host also quantises the input, as in `IntNet`.

## Host interface and control

* Memory-mapped 32-bit port: write / read any memory (act, weight, param, descriptor), CSR `START`, `DONE`,
  cycle counters (total, per pass, stall).
* Descriptor per pass (compiler-generated): kernel (1 / 3), stride, H_in, W_in, H_out, W_out, Cin/8, Cout/64,
  input buffer + base + layout, output buffer + base + layout, residual buffer + base + mode, weight base, param
  base, idm0 / idsh. Then a head descriptor.
* The weights, params and descriptors are loaded once. Per image the host writes the input plane, starts, and
  reads the 10 logits.

## Reference models (bit-exact chain)

`IntNet` (qc18/int8.py) == compiler golden model (numpy, the exact pass schedule, memory images) == RTL (VCS) ==
gate-level netlist (VCS, zero-delay + SDF). Checks: logits int32 equal; in RTL also every stored map.

## Ablation designs (same array geometry, same buffers, same flow)

1. **dense int8 PE**: 8x8 int8 weights per block (512 b / block), 64 multipliers + adder tree per PE.
2. **ternary PE**: 2-b weight per entry (128 b / block), 64 trit-selects + adder tree per PE (no QC structure).
3. **QC PE** (this design): 10 b / block, 2 rotators + 8 adders.

Weight memory: the QC codes (218 KB) are on-chip. Ternary (2.8 MB) and int8 (11.2 MB) do not fit in a 65 nm
die of this class: they are evaluated both with on-chip SRAM scaled from compiler datatables (MODELLED) and with
off-chip DRAM at a cited pJ/bit (MODELLED).

## Appendix: memory images and descriptors (compiler `qc18acc/compile`)

All images are produced by `qc18acc.compile.program.build` and consumed only through these formats by the golden
model (`golden.py`) and the RTL. Hex files are `$readmemh` style: one word per line, MSB first, no prefix.

**Activation buffers** A = 0, B = 1, C = 2: 8 banks x 1024 x 64 b each (`act_<A|B|C>_b<k>.hex`, 16 digits).
Word lane i = bits [8i+7 : 8i] = int8 channel 8 cb + i. Tensor element (cb, y, x) is at bank `index mod 8`,
address `base + (index >> 3)` with `index` as in "Map layout". All bases are 0 (each buffer holds one live tensor;
the compiler checks liveness and capacity). Tensors of s8kd (layout R = raster, P = phase):

| tensor | buffer | layout | words |
|---|---|---|---|
| input image (3 ch + 5 zero lanes) | C | R | 1024 |
| stem, blocks 0, 1 outputs / c1 maps (64x32x32) | rotating | R (P for block 1 output) | 8192 |
| block 2/4/6 sc output R (int16, 2 planes per group) | Z | R | 8192 / 4096 / 2048 |
| other maps | rotating | R, or P if the consumer is a stride-2 pass | C H W / 8 |

The exact per-pass assignment is printed by `main.py` and written to `program.txt` by the export.
R planes: R channel group cb -> plane 2 cb = low bytes (lane i = bits 7:0 of R[8 cb + i]), plane 2 cb + 1 = high
bytes (bits 15:8, so R = 256 * signed(high) + unsigned(low)).

**Weight SRAM** (80 b, `weights.hex`, 20 digits). Per conv pass, from `wbase`: words in order og, kh, cb, kw
(`og` outer; v2, `layout.tap_order`; kw sequence 0, 1, 2 or, for stride-2 3x3 passes, 0, 2, 1), `cout64 * k * k * cin8` words. Word bits [10g+9 : 10g] = code of block (row group og*8 + g, column
block (kh, kw, cb)). Code bits [4:0] = term 1 = {k1[2:0], t1[1:0]}, bits [9:5] = term 2; trits 00 = 0, 01 = +1,
11 = -1 (10 illegal); canonical: nonzero terms first in ascending shift, unused terms (0, 00). The code is of the QC
matrix `M` (not `d M`); the sign `d` is in the param word. After the conv weights, the FC words (head `wbase`):
`64 x 10` words in order cb (outer), class j (inner); bits [8 lane + 7 : 8 lane] = int8 `W8[j, 8 cb + lane]`,
bits [79:64] = 0. (Deviation from "Head" above, which places the FC weights in the param SRAM: they are 80-b
weight words so the param SRAM keeps one word format.)

**Param SRAM** (72 b, `params.hex`, 18 digits). Per conv pass, from `pbase`: one word per output channel c
(64 per og, loaded into the PPU register file at each og change): bits [31:0] bias (int32), [62:32] m0 (31 b),
[68:63] sh (6 b), [69] d (1 = negate the accumulator), [71:70] 0. After the conv params, at the head `pbase`:
10 words with the FC bias in [31:0] (other fields 0).

**Descriptor RAM** (32 b, `desc.hex`, 8 digits): 8 words per pass, pass descriptors in execution order, then
the head descriptor (the only one with `last` = 1). Conv pass:

| word | bits |
|---|---|
| 0 | [1:0] type = 1, [3:2] k (1 / 3; pad = k >> 1), [5:4] stride (1 / 2), [7:6] mode (0 RELU, 1 RAW16, 2 RES_ID, 3 RES_R), [8] in layout, [9] out layout, [10] res layout (0 raster, 1 phase), [12:11] in buffer, [14:13] out buffer, [16:15] res buffer, [17] last |
| 1 | [7:0] H_in, [15:8] W_in, [23:16] H_out, [31:24] W_out |
| 2 | [15:0] Cin / 8 (stem: 1), [31:16] Cout / 64 |
| 3 | [9:0] in base, [19:10] out base, [29:20] res base |
| 4 | weight base (word address) |
| 5 | param base (word address) |
| 6 | idm0 (31 b; RES_ID only) |
| 7 | idsh (6 b; RES_ID only) |

Head: word 0 type = 2, [8] in layout, [12:11] in buffer, [17] last = 1; word 1 [7:0] H, [15:8] W (4, 4);
word 2 [15:0] C / 8 (64), [31:16] number of classes (10); word 3 in base; word 4 FC weight base; word 5 FC bias
param base; word 6 pool m0; word 7 pool sh. The pool requant is `clamp((sum16 * m0 + 2^(sh-1)) >>> sh, 0, 127)`.

**Per-image files** (`main.py --export DIR --images ...`, `DIR/img<n>/`): initial `act_*_b*.hex` (input plane
in C, everything else 0), `input.hex` (1024 words in raster index order), `logits.hex` / `logits.txt` (10 int32 =
FC accumulator + bias), `pass<ii>_<name>.hex` (the output buffer after pass ii, 8192 lines, line = bank * 1024 +
address; words not written by the pass are `x`). `DIR/program.txt` lists the passes, buffers, bases and sizes.

**Act-read model** (`golden.act_reads`, v2): per pass the kw-window bank reads (`layout.window_plan`) and the v1
count (one per valid lane); equal to the RTL counter `CSR_ACT_RD` (0x0d) per image.

**Cycle model** (`golden.cycles`, a MODEL, unchanged in v2): per pass `tiles * max(K, drain) + 64 * Cout/64` with
`tiles = H_out W_out / 8 * Cout / 64`, drain 64 cycles (128 for RAW16 / RES_R), and a head estimate
`64 * (16 + 10) + 16`.

## v3 (implemented): two blocks per PE per cycle (Kb = 2)

Implemented in `compile3/` (compiler re-pack + golden), `hw3/` (RTL, tech mapping, TB), `impl/v3/` (macros); v2 is
unchanged and still built by default (`QA_V=3` selects v3 in `impl/run.sh`, `gls/run_gls.sh`, `power/power.sh`,
`power/energy.py`).  Results and every measured / synthesis-estimated / modelled number: `results/v3.md`.
The text below is the plan, with the implementation notes and deviations marked **[impl]**.

**Why (measured, `results/power_v2.md`, PE-internal breakdown).** 68 % of a PE's power is paid once per
accumulator update, whatever the work per update: clock gates and register clock pins 35 %, the 20-b accumulate
adders 27 %, accumulator data 6 %. The QC work per block (rotators 7 %, trits + 2-term adds 21 %) is the small part.
Summing two blocks before each accumulate amortises the fixed part. Prediction (to check against the measurement):
PE energy per block about x0.7; cycles per image about x0.53 (so leakage and control energy per image about x0.55);
image energy about 92 -> ~70 uJ at 400 MHz; throughput about x1.9. With Kb = 2, the per-block reduction is a larger
share of PE energy than at Kb = 1, so the QC-vs-ternary gap should widen (ablation rerun at Kb = 2).
**[impl]** Measured (`results/v3.md`, image 0, 400 MHz tt, SDF SAIF, +dat): 81 438 cycles / image (x0.509),
68.5 uJ / inference (-2.2 % vs ~70), PE array energy per QC block x0.684, 4 912 inferences / s (x1.96); 6.514 mm2,
816.4 kGE, fmax unchanged (ss 303.2 MHz).  Control energy is x0.765, not x0.55: the xbar's data volume is not
cycle-proportional (results/v3.md 5.3).  The ablation rerun at Kb = 2 is not done (open).

* **Pairs of input-channel groups.** A PE consumes, per cycle, the blocks of input-channel groups `cb = 2j` and
  `2j + 1` of the same tap (kh, kw). `y_i += B_even x_even + B_odd x_odd`, written as ONE combinational sum
  `acc + 4 trit terms` (no hierarchy split between the term adds and the accumulate: the v2 split cost +4.8 mW of
  glitching). Tap order per tile: kh, cb pair, kw. K per tile = kh * kw * ceil(Cin / 16). Stem: Cin / 8 = 1, so the
  odd block code is 0 and contributes nothing. Every other conv has an even Cin / 8.
* **Activation word = 128 b** = channel groups 2j (low half) and 2j + 1 (high half) of one pixel.
  `index = cbp * H * W + pix`, bank = index mod 8, as in v2. Each bank has two macros of 64 b x 512 (lo / hi) with
  separate enables, so the PPU / head can read or write 64-b halves. Capacity is unchanged: 3 x 64 KiB. The macro
  shape comes from a sweep: rf_sp_adv 512 x 64, or one 512 x 128 if legal and denser. The kw window holds 128-b words.
* **Weights.** 160 b per array cycle = 8 columns x (even code, odd code). The weight memory is split into an even
  half and an odd half, each 3 x 4096 x 80 b, read in parallel. FC words are in the even half.
* **PPU: 16 lanes, two output words per cycle** = channel groups 2m and 2m + 1 of one pixel = the lo and hi halves
  of one bank word. The drain takes columns 2m and 2m + 1 per cycle, so a tile drains in 32 cycles (layer 1 has
  K = 36 >= 32). Width: `v = acc + bias` is held in 20 b. The compiler proves |v| < 2^19 per layer (v2 measured
  max 105 140 < 2^17) and refuses networks that exceed it, so the multipliers are 20 x 31 (v2: 32 x 31).
  RES_R / RAW16 need 4 int8 planes per pair, i.e. two bank words of the same bank, so they take 2 cycles per pair.
* **Unchanged:** the AGU index rule and layouts, the kw window logic (on 128-b words), the head, host, descriptors
  (fields for pairs where needed), the 8 x 8 geometry, accumulator width, clock gating of macros, and the bit-exact
  chain.

**[impl] notes and deviations.**

* Compiler (`compile3/program.py`): v3 is a re-pack of the v2 program (`from_v2`): same pass schedule, buffers,
  layouts, params and descriptors (the descriptor keeps `cin8` = group count; the AGU derives ceil(cin8 / 2)).
  Weight word of step (og, kh, j, kw): even half = v2 word of tap (kh, kw, 2j), odd half = (kh, kw, 2j + 1) or a
  zero word (stem); both halves at the same address `wbase + og*S + s`; FC words in the even half after the convs.
  Proofs added: |d acc + bias| < 2^19 (max 105 140 over all layers, worst case), |bias| < 2^19.  Golden
  `compile3/golden.py` (GEMM path + literal 4-term path through the 128-b window).
* int16 R planes (RAW16 / RES_R): output pair j -> pair plane 2j = low bytes of groups 2j, 2j + 1, pair plane
  2j + 1 = high bytes (int8 group order lo(2j), lo(2j + 1), hi(2j), hi(2j + 1)); the two words are in the same bank
  (index + H W), 2 cycles per pair word as planned.
* Act macros: sweep `impl/v3/sweep_result.txt`: rf_sp_adv 512 x 64 mux 4 (53 045 um2) is the densest legal
  shape; 512 x 128 exists only as sram_sp_adv mux 8 (167 678 um2 > 2 x 53 045).  48 x `qa_act_512x64m4`
  (2.546 mm2 vs v2 24 x 1024x64 2.756 mm2).  The array reads both halves of a bank word (also for the stem, whose
  high half is zero), the head one half, the PPU whole words, the host 64-b halves (host act address bit 0 = half;
  weight address bit 14 = odd half).
* PE (`hw3/rtl/qa_pe.sv`): 4 rotators (`u_rot1..4`) + one module `u_acc` (`qa_pe_acc4`) computing per lane
  `(first ? 0 : acc) + sum_k ((sext(e_k ? x_k : 0) ^ n_k) + n_k)` as one 6-operand sum (the four +n carry-ins are one
  3-b operand), so no hierarchy split between the term adds and the accumulate.  DC clock gating as v2.
* Drain: 2 columns per read, 32 reads per tile (64 cycles for RAW16 / RES_R); PPU 16 lanes, bias kept 20 b in the
  RF, `v` 20 b, multiplier 20 x 31 (two 20 x 16 / 20 x 15 partial products as v2); the 64-b rounding sum kept.
* Head: unchanged schedule / arithmetic; group cb is the half cb[0] of pair plane cb >> 1 (one half enabled).
* Weight memory: 2 x `qa_bankmem` (3 x 4096 x 80, `u_wmem_e` / `u_wmem_o`), same 6 macros as v2.

## v4 (planned): 16 pixel rows (128 PEs) and registered macro boundaries

**Why (v3 measurements).**
1. *Clock.* v3 meets tt 463 MHz pre-route, but the routed (provisional) design reaches only tt 295 / ss 185 MHz.
   The limiting paths start or end at SRAM macros:
   - weight macro -> head FC dot (pre-route critical path);
   - the weight-macro clock arriving 0.48 ns late through the CTS sink buffers;
   - hold failures at the weight-macro data inputs (host write path).
2. *Array size.* Macros are about 5.3 of 6.5 mm2 pre-route; the 64 PEs are about 0.5 mm2. Peak throughput per mm2
   is therefore set by the memory, not by compute. Doubling the PEs costs little area.

**Changes.**
* **Registered macro boundaries (fix 1).**
  - Every macro (weight, act, param, descriptor) gets an output register in the same clock domain. The read
    latency becomes 2 cycles; the AGU / sequencer / PPU / head pipelines absorb the extra stage, and pass
    start-up costs +1 cycle.
  - Address, data and enable inputs of every macro are driven directly by flops with no logic between them and
    the macro pin. The host write path into the weight / param macros is registered too.
  - The head FC dot is pipelined so that no path runs from a macro Q to the dot output in one cycle.
  - Target: the pre-route critical path is inside logic (PE or PPU), not at a macro.
* **16 pixel rows (fix 3).**
  - The array becomes 16 rows (output pixels) x 8 columns (output-channel groups) = 128 PEs, each unchanged from
    v3 (Kb = 2, fused `acc + 4 trit terms`).
  - The weight word (160 b per cycle) is broadcast to all 16 rows, so the weight memory and its bandwidth are
    unchanged. Weight read energy per block op halves.
  - The output tile is 16 consecutive output pixels x 64 channels. The last stage (4 x 4 maps) is exactly one tile.
  - Columns are not widened: stage-1 layers have only 64 output channels.
* **Activation buffers.**
  - 16 pixels x 128 b are read per cycle, so bank = index mod 16 (conflict-free for 16 consecutive indices, in
    both raster and phase layout).
  - Capacity is unchanged: 3 x 64 KiB = 16 banks x (lo, hi) x 256 x 64 b.
  - Choose the macro shape by sweep: rf_sp_adv 256 x 64 versus alternatives with the same capacity. Report the
    area cost against v3's 512 x 64.
  - The kw window covers 16 pixels plus the halo.
* **Drain / PPU.**
  - A 16 x 64 tile holds 1024 accumulators. At 16 lanes it drains in 64 cycles, against K = 36 for the 64-channel
    layers, which would stall.
  - Provide 32 PPU lanes, so a tile drains in 32 cycles, writing 2 bank words of different pixels per cycle.
  - Use the cycle model to decide: if 16 lanes lose < 3 % of cycles per image, keep 16 and report both.
  - RES_R / RAW16 stay at 2 cycles per pair.
* **Unchanged:** the QC codes and weight image (word for word), the pass schedule, buffers A/B/C, the layouts, the
  bounds and proofs, the head arithmetic, the host and descriptors (add fields only where needed), and the
  bit-exact chain.

**Prediction (to check).**

| Quantity | v3 measured | v4 predicted |
|---|---|---|
| Cycles / image | 81,438 | ~44k (ideal at 128 PEs x 2 blocks: 33.9k; stem padding, drains and pass overheads add ~30 %) |
| Logic area | 816 kGE | about +0.6M GE: +64 PEs at 7.9 kGE, +16 PPU lanes |
| Total area, pre-route | 6.5 mm2 | ~7.5 mm2 |
| Energy / inference at 400 MHz tt | 68.5 uJ | ~55-60 uJ: PE energy per block unchanged; leakage, control and weight reads per image about halve |
| Pre-route tt fmax | 463 MHz | >= v3, set by the PE / PPU, not by macros |

* Target after OpenROAD P&R (improved recipe): tt >= 400 MHz.
* Throughput at 400 MHz: ~9k inferences/s, ~10 dense-equivalent TOPS, ~1.3 TOPS/mm2 pre-route.
