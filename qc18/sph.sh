# Spherical Adam + AdamW confirmations (60 epochs, val only).  The hard projection is per-row scale-invariant, so
# --qopt sphere fixes each block row of theta at unit RMS and the (cosine) Adam lr sets the angular step directly.
# Also: gibbs + AdamW, seed repeats, KD on top of AdamW, unsigned with AdamW.  Run up to 3 at a time on one GPU.
P="python3 -m qc18.train --epochs 60 --test 0 --mode signed"; O=/tmp/${USER:-$(whoami)}/qc18/sph
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qopt sphere --qlr 5e-3 --out $O/s8_sph05
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qopt sphere --qlr 1e-2 --out $O/s8_sph10
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qopt sphere --qlr 2e-2 --out $O/s8_sph20
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 1.0 --tau1 1.0 --qwd 0.1 --out $O/s8_g1_aw10
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 0.5 --tau1 0.5 --qwd 0.1 --out $O/s8_g05_aw10
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qwd 0.1 --seed 1 --out $O/s8_ste_aw10_s1
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 1.0 --tau1 1.0 --qwd 0.1 --seed 1 --out $O/s8_g1_aw10_s1
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qwd 0.1 --kd 0.5 --kd-t 4 --teacher /tmp/${USER:-$(whoami)}/qc18/pilot/dense/best.pt --out $O/s8_aw10_kd
P="python3 -m qc18.train --epochs 60 --test 0 --mode unsigned"
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qwd 0.1 --bn-sign 1 --qinit-k 2 --out $O/u8_aw10
