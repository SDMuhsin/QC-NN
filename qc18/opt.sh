# Optimizer sweep (60 epochs, val only): is theta under-trained by Adam?  sgdeq = dense SGD projected onto the
# circulant subspace (theta lr = lr/b, wd = wd*b, same nesterov/warmup/cosine).  rc*: real-weight relaxations (NOT QC).
# Run up to 3 at a time on one GPU.
P="python3 -m qc18.train --epochs 60 --test 0 --mode signed"; O=/tmp/${USER:-$(whoami)}/qc18/opt
CUDA_VISIBLE_DEVICES=0 $P --b 2 --relax circ --qopt sgdeq --out $O/rc2_eq
CUDA_VISIBLE_DEVICES=0 $P --b 8 --relax circ --qopt sgdeq --out $O/rc8_eq
CUDA_VISIBLE_DEVICES=0 $P --b 2 --estimator ste --qopt sgdeq --out $O/s2_eq
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qopt sgdeq --out $O/s8_eq
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 1.0 --tau1 1.0 --qopt sgdeq --out $O/s8_g1_eq
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qopt adam --qwd 0.05 --out $O/s8_adamw
# sgdeq helped the relaxation (rc2_eq), so: theta lr scale 2/b, wd scale 0.5*b
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qopt sgdeq --eq-lr 2 --out $O/s8_eq_lr2
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qopt sgdeq --eq-wd 0.5 --out $O/s8_eq_wd
