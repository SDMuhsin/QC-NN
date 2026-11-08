# Diagnostic sweep (60 epochs, val only): where does the signed b=8 QC gap to dense (88 vs 94.4) come from?
# r_*: real-weight relaxations (NOT QC, do not verify); s2/s4: block size; kd: distillation; s1: seed noise.
# Run up to 3 at a time on one GPU.
P="python3 -m qc18.train --epochs 60 --test 0 --mode signed"; O=/tmp/${USER:-$(whoami)}/qc18/diag; T=/tmp/${USER:-$(whoami)}/qc18/pilot/dense/best.pt
CUDA_VISIBLE_DEVICES=0 $P --b 8 --relax circ --out $O/r_circ8
CUDA_VISIBLE_DEVICES=0 $P --b 8 --relax top2 --estimator ste --out $O/r_top8
CUDA_VISIBLE_DEVICES=0 $P --b 2 --estimator ste --out $O/s2_ste
CUDA_VISIBLE_DEVICES=0 $P --b 2 --estimator gibbs --tau0 1.0 --tau1 1.0 --out $O/s2_g1
CUDA_VISIBLE_DEVICES=0 $P --b 4 --estimator ste --out $O/s4_ste
CUDA_VISIBLE_DEVICES=0 $P --b 4 --estimator gibbs --tau0 1.0 --tau1 1.0 --out $O/s4_g1
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 1.0 --tau1 1.0 --kd 0.5 --kd-t 4 --teacher $T --out $O/s8_g1_kd
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --seed 1 --out $O/s8_ste_s1
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 1.0 --tau1 1.0 --seed 1 --out $O/s8_g1_s1
CUDA_VISIBLE_DEVICES=0 $P --b 2 --relax circ --out $O/r_circ2
