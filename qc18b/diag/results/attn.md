# Attention-map agreement with FP (measured)

BIN `/tmp/root/qc18b/init200/I0/best.pt`, BIN-scratch (SCR) `/tmp/root/qc18b/arch/PK60_200/best.pt`, FP `/tmp/root/qc18b/final/s8kd_s0/best.pt`; val[:2000], eval, fp32. FPflip = FP on horizontally flipped inputs, maps flipped back (reference).

larq_zoo `AttentionMatchingLossLayer` (Real-to-Binary sec. 4.2): tensor = block output (Lambda `{name}_out`, after the skip add, before the next block's BN/sign; here s_k pre-ReLU); map = `reduce_mean(square(a), axis=-1)` (mean over channels), flattened, divided by per-image max (not L2); loss = `reduce_mean(square(qs - qt), axis=-1)` per image (then mean over layers x loss_weight). cos = per-image cosine of the flattened maps (scale invariant), mean over images; r2b = mean over images of the per-image loss.

## s_k (pre-ReLU)

| block | HxW | cos BIN-FP | cos SCR-FP | cos FPflip-FP | r2b BIN-FP | r2b SCR-FP | r2b FPflip-FP |
|---|---|---|---|---|---|---|---|
| 0 | 32x32 | 0.938 | 0.935 | 0.978 | 0.0994 | 0.1127 | 0.0053 |
| 1 | 32x32 | 0.932 | 0.922 | 0.967 | 0.0356 | 0.0206 | 0.0078 |
| 2 | 16x16 | 0.954 | 0.946 | 0.989 | 0.0363 | 0.0366 | 0.0077 |
| 3 | 16x16 | 0.925 | 0.910 | 0.982 | 0.0755 | 0.0543 | 0.0081 |
| 4 | 8x8 | 0.963 | 0.961 | 0.989 | 0.0447 | 0.0479 | 0.0091 |
| 5 | 8x8 | 0.961 | 0.957 | 0.982 | 0.0489 | 0.0473 | 0.0137 |
| 6 | 4x4 | 0.980 | 0.987 | 0.986 | 0.0319 | 0.0172 | 0.0167 |
| 7 | 4x4 | 0.976 | 0.977 | 0.985 | 0.0275 | 0.0247 | 0.0128 |

## relu(s_k)

| block | HxW | cos BIN-FP | cos SCR-FP | cos FPflip-FP | r2b BIN-FP | r2b SCR-FP | r2b FPflip-FP |
|---|---|---|---|---|---|---|---|
| 0 | 32x32 | 0.967 | 0.960 | 0.980 | 0.0290 | 0.0500 | 0.0069 |
| 1 | 32x32 | 0.941 | 0.938 | 0.968 | 0.0221 | 0.0212 | 0.0099 |
| 2 | 16x16 | 0.956 | 0.947 | 0.989 | 0.0346 | 0.0398 | 0.0090 |
| 3 | 16x16 | 0.920 | 0.905 | 0.975 | 0.0374 | 0.0457 | 0.0113 |
| 4 | 8x8 | 0.962 | 0.954 | 0.983 | 0.0352 | 0.0426 | 0.0144 |
| 5 | 8x8 | 0.925 | 0.932 | 0.976 | 0.0535 | 0.0584 | 0.0155 |
| 6 | 4x4 | 0.951 | 0.945 | 0.916 | 0.0272 | 0.0320 | 0.0400 |
| 7 | 4x4 | 0.956 | 0.958 | 0.953 | 0.0206 | 0.0207 | 0.0202 |

## b1 of block k+1 (1-bit, input s_k): per-position L2 norm map vs FP relu(s_k)

cos_l2: vs FP per-position L2 norm of relu(s_k); cos_att: vs FP attention map of relu(s_k); FPflip row: FP relu(s_k) L2 map on flipped inputs vs FP.

| k | cos_l2 BIN | cos_l2 SCR | cos_att BIN | cos_att SCR | cos_l2 FPflip |
|---|---|---|---|---|---|
| 0 | 0.985 | 0.985 | 0.942 | 0.942 | 0.995 |
| 1 | 0.988 | 0.984 | 0.948 | 0.938 | 0.992 |
| 2 | 0.993 | 0.993 | 0.972 | 0.972 | 0.997 |
| 3 | 0.985 | 0.982 | 0.939 | 0.933 | 0.994 |
| 4 | 0.992 | 0.991 | 0.968 | 0.966 | 0.996 |
| 5 | 0.987 | 0.987 | 0.944 | 0.944 | 0.993 |
| 6 | 0.977 | 0.966 | 0.886 | 0.862 | 0.972 |
