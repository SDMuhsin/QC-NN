#!/bin/bash
# Homotopy (relaxed -> hard training forward) at b=8 signed, AdamW --qwd 0.1, 60 epochs, val only, seeds 0/1
# -> /tmp/$USER/qc18/hom/<name>_s<seed>.  hg*: Gibbs mean, tau tau0 -> 0.01 tau0 over the first F of training;
# hr: ramp (1-lam) top2/alpha + lam hard.  Run up to 3 at a time on GPU 0:
#   nohup qc18/ablate_driver.sh qc18/homotopy.sh > /tmp/$USER/qc18/hom/driver.out 2>&1 &
P="python3 -m qc18.train --epochs 60 --test 0 --mode signed --b 8 --estimator ste --qwd 0.1"; O=/tmp/${USER:-$(whoami)}/qc18/hom
CUDA_VISIBLE_DEVICES=0 $P --homotopy gibbs --tau0 1.0 --h-frac 0.5 --seed 0 --out $O/hg1_f50_s0
CUDA_VISIBLE_DEVICES=0 $P --homotopy gibbs --tau0 0.3 --h-frac 0.5 --seed 0 --out $O/hg03_f50_s0
CUDA_VISIBLE_DEVICES=0 $P --homotopy gibbs --tau0 1.0 --h-frac 0.8 --seed 0 --out $O/hg1_f80_s0
CUDA_VISIBLE_DEVICES=0 $P --homotopy ramp --h-frac 0.5 --seed 0 --out $O/hr_f50_s0
CUDA_VISIBLE_DEVICES=0 $P --homotopy gibbs --tau0 1.0 --h-frac 0.5 --seed 1 --out $O/hg1_f50_s1
CUDA_VISIBLE_DEVICES=0 $P --homotopy gibbs --tau0 0.3 --h-frac 0.5 --seed 1 --out $O/hg03_f50_s1
CUDA_VISIBLE_DEVICES=0 $P --homotopy gibbs --tau0 1.0 --h-frac 0.8 --seed 1 --out $O/hg1_f80_s1
CUDA_VISIBLE_DEVICES=0 $P --homotopy ramp --h-frac 0.5 --seed 1 --out $O/hr_f50_s1
