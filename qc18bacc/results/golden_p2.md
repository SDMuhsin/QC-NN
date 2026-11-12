# golden_p2: power-of-two residual-stream scale ladder vs IntBin (val, 5000 images)

`CUDA_VISIBLE_DEVICES=0 python3 -m qc18bacc.golden_p2 RUN/best.pt` (qc18bacc/golden_p2.py, subclass of qc18b.int_bin.IntBin).
S_0 = max|s_0|/32767 (train[:2000], float_trace); S_k = S_0 2^-e_k, e_k = largest e with S_0 2^-e >= max|s_k|/32767.
Ladder injected as calibration maxima v_0 2^-e_k (fp64-exact), so all dependent quantities (stem_m, c2m/c2h, scm/sch, T1,
hm, fp-block scales, pool_m, idm) are recomputed by IntBin's own code. Asserted: every S_{k-1}/S_k == 2^j exactly, every
idm == (m0 2^30, sh 30-j), and requant(x, idm) == x<<j / round-half-up >>-j for all x in [0, 32767] (blocks 0,1,3,5,7).
IntBin reproduces intbin.txt (3192/5000 sat 19; 3176/5000 sat 17). Bootstrap: 1000 paired resamples, seed 0.

| seed | IntBin val | golden_p2 val | diff (pt) | 95 % CI (pt) | argmax disagree | sat IntBin | sat p2 |
|---|---|---|---|---|---|---|---|
| E6_s0 | 63.84 % (3192) | 64.04 % (3202) | +0.20 | [-0.58, +0.98] | 768 | 19 | 0 |
| E6_s1 | 63.52 % (3176) | 63.90 % (3195) | +0.38 | [-0.42, +1.16] | 712 | 17 | 8 |

Ladder (k = 0..8; e_k, S_k(ladder)/S_k(calibrated)):

| seed | | s0 | s1 | s2 | s3 | s4 | s5 | s6 | s7 | s8 |
|---|---|---|---|---|---|---|---|---|---|---|
| E6_s0 | e_k | 0 | 0 | -1 | 0 | 0 | -1 | -1 | -2 | -2 |
| E6_s0 | ratio | 1.0000 | 1.2256 | 1.7017 | 1.3434 | 1.4875 | 1.3640 | 1.2419 | 1.1598 | 1.1348 |
| E6_s1 | e_k | 0 | -1 | -1 | -1 | -1 | -1 | -1 | -3 | -3 |
| E6_s1 | ratio | 1.0000 | 1.3846 | 1.3637 | 1.3786 | 1.8946 | 1.0372 | 1.0517 | 1.4891 | 1.3836 |

Identity-shortcut shifts (block, j with S_{k-1}/S_k = 2^j): s0 (0,0) (1,-1) (3,0) (5,0) (7,0);
s1 (0,-1) (1,0) (3,0) (5,0) (7,0). Remaining p2 saturations (s1: 8) are val values beyond the train[:2000] range.
Conclusion: power-of-two ladder costs no accuracy (both seeds +0.2/+0.4 pt, CIs include 0); identity requant becomes a shift.
