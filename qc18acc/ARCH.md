# QC18-ACC: architecture spec (v1)

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
  one (kh, kw, cb). Words are ordered per pass as `og` (64-channel group), then kh, kw, cb, which is the order
  the array consumes them.
* **Channel params** (per conv output channel, 72-b word): `bias` int32, `m0` 31 b (unsigned), `sh` 6 b, `d` 1 b
  (1 = negate the accumulator), 2 b spare.

## PE array: 8 rows (pixels p) x 8 columns (output groups g)

* Row p receives the activation word of tile pixel `o0 + p` for the current (kh, kw, cb). It is zero if padded.
* Column g receives the code of block (og*8 + g, kh, kw, cb).
* PE(p, g): two 8-lane rotators (3-stage log shifter, 8-b lanes), trit apply (negate / zero, 9 b), 8 adders,
  8 accumulators of 20 b. The worst case is 2 * 576 * 127 < 2^18, and the compiler asserts the bound per layer.
* Output-stationary. A tile (8 pixels x 64 channels) accumulates over `K = kh*kw*Cin/8` cycles, one block per
  PE per cycle (stem: Cin padded to 8, K = 9). At the end of a tile the accumulators move to a shadow register
  in 1 cycle and the next tile starts.
* Drain: the shadows of column g form a chain along p. The PPU takes one word (8 lanes = 8 channels of one pixel)
  per cycle in the order `p` outer, `g` inner, and each column chain shifts once per 8 cycles. A tile drain takes 64
  cycles. If the next tile ends before the drain is done, the array stalls (stem K = 9, 1x1 shortcuts K = 8..32).
* Pipeline: the AGU + SRAM read and the code read are aligned to the same cycle. Register stages are free, and
  are documented in the RTL.

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

**Weight SRAM** (80 b, `weights.hex`, 20 digits). Per conv pass, from `wbase`: words in order og, kh, kw, cb
(`og` outer), `cout64 * k * k * cin8` words. Word bits [10g+9 : 10g] = code of block (row group og*8 + g, column
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

**Cycle model** (`golden.cycles`, a MODEL): per pass `tiles * max(K, drain) + 64 * Cout/64` with
`tiles = H_out W_out / 8 * Cout / 64`, drain 64 cycles (128 for RAW16 / RES_R), and a head estimate
`64 * (16 + 10) + 16`.
