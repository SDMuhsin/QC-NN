# QC-GeMMX: architecture spec (v1)

Base: the KUL SNAX cluster with GeMMX (`hw/kulcluster`), unchanged except the GeMM core and the B (weight) streamer.
Target: `qc/` model **s2** (b = 2, signed).  In the GEMM view `W[cout, (kh,kw,cin)]` every 2x2 block is
`[[a, b], [b, a]] = a*I + b*P` with `a, b in {-1, 0, 1}`; rows with a negative BN scale are stored as `-M`.

## Datapath (same 8x8x8 shape: M = 8 pixels, K = 8 input channels, N = 8 output channels per fire)
* A (512 b), C (bias, int32), D (int32 / int8 via RescaleSIMD) interfaces and streamers: **unchanged**.
* Per mesh row (pixel m): `x_k = a_k - subtraction_a` (9 b), then a shared 2-point Hadamard butterfly per input
  pair p = 0..3: `s_p = x_2p + x_2p+1`, `d_p = x_2p - x_2p+1` (10 b).  8 adders per row, shared by all 8 columns.
* Tile (m, n): `sum_{p=0..3} sel(code[n][p])`, `sel in {0, +-x_2p, +-x_2p+1, +-s_p, +-d_p}`: 4 muxes + 3 adders
  (dense tile: 8 multipliers 9x9 + 7 adders).  Accumulator, add-C and control: unchanged.
* Column decoder (once per column, shared along the 8 rows): block (j = n/2, p) with weights (a, b):
  even n -> coefficients (a, b) on (x_2p, x_2p+1); odd n -> (b, a).  Both nonzero: a == b -> a*s, a == -b -> +-d;
  one nonzero -> +-x; none -> 0.
* B: **64 b per 8x8 weight tile** = 16 block codes x 4 b (block index j*4 + p; bits [1:0] = a, [3:2] = b;
  trit code 00 = 0, 01 = +1, 11 = -1).  Dense: 512 b per tile -> 8x less weight storage and B traffic.
  The B reader becomes 1 channel of 64 b (was 8 x 64 b).

## Mapping / software (reuse `nn/compile`, `nn/sw`)
* Requant: s2 has one multiplier / shift per **output channel**; the RescaleSIMD has 8 lanes -> one GeMMX call
  per 8-output-channel group (N = 1 per call), CSRs reprogrammed per call (v1, no hardware change).
* Sign-flipped rows (`-M`): store M, negate the bias (C) and the requant multiplier (the SIMD multiplier is
  signed: `floor((-acc)(-m) / 2^s) = floor(acc m / 2^s)` exactly).  No hardware.
* Residual adds, pool + FC: unchanged (cores), identical to the dense baseline.

## Comparisons (same flow, same clocks)
1. baseline: dense ResNet-8 on GeMMX (`nn/`, kul_w4.2p): 401.7 k cyc, ~101 uJ / image.
2. control: s2 on unmodified GeMMX (int8 weights in {-1,0,1}, same per-group calls): isolates model vs hardware.
3. QC-GeMMX running s2.   Ablation (array-level synthesis only): int8 MAC tile vs ternary-select tile (no
   butterfly, 8 terms) vs QC butterfly tile.
