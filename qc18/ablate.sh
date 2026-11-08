#!/bin/bash
# Ablation batch (60 epochs, val only, AdamW --qwd 0.1 unless stated) -> /tmp/$USER/qc18/abl/<name>_s<seed>.
# rc*/rt8: real-weight relaxations (NOT QC); s2/s4: block size; s8adam: plain Adam; u2*: unsigned-collapse fixes;
# s8kd: distillation.  One run per line; run up to 3 at a time on GPU 0 (qc18/ablate_driver.sh).
P="python3 -m qc18.train --epochs 60 --test 0 --estimator ste"; O=/tmp/${USER:-$(whoami)}/qc18/abl; T=/tmp/${USER:-$(whoami)}/qc18/pilot/dense/best.pt
CUDA_VISIBLE_DEVICES=0 $P --mode unsigned --b 2 --qwd 0.1 --seed 0 --out $O/u2nofix_s0
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 2 --relax circ --qwd 0.1 --seed 0 --out $O/rc2_s0
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 4 --relax circ --qwd 0.1 --seed 0 --out $O/rc4_s0
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --relax circ --qwd 0.1 --seed 0 --out $O/rc8_s0
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --relax top2 --qwd 0.1 --seed 0 --out $O/rt8_s0
CUDA_VISIBLE_DEVICES=0 $P --mode unsigned --b 2 --bn-sign 1 --qwd 0.1 --seed 0 --out $O/u2sign_s0
CUDA_VISIBLE_DEVICES=0 $P --mode unsigned --b 2 --qinit-k 2 --qwd 0.1 --seed 0 --out $O/u2k2_s0
CUDA_VISIBLE_DEVICES=0 $P --mode unsigned --b 2 --bn-sign 1 --qinit-k 2 --qwd 0.1 --seed 0 --out $O/u2both_s0
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 2 --qwd 0.1 --seed 1 --out $O/s2_s1
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 4 --qwd 0.1 --seed 1 --out $O/s4_s1
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --qwd 0 --seed 2 --out $O/s8adam_s2
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --qwd 0.1 --kd 0.5 --kd-t 4 --teacher $T --seed 1 --out $O/s8kd_s1
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 2 --relax circ --qwd 0.1 --seed 1 --out $O/rc2_s1
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 4 --relax circ --qwd 0.1 --seed 1 --out $O/rc4_s1
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --relax circ --qwd 0.1 --seed 1 --out $O/rc8_s1
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --relax top2 --qwd 0.1 --seed 1 --out $O/rt8_s1
CUDA_VISIBLE_DEVICES=0 $P --mode unsigned --b 2 --bn-sign 1 --qwd 0.1 --seed 1 --out $O/u2sign_s1
CUDA_VISIBLE_DEVICES=0 $P --mode unsigned --b 2 --bn-sign 1 --qinit-k 2 --qwd 0.1 --seed 1 --out $O/u2both_s1
