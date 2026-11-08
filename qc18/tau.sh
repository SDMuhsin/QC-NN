# Temperature curve + seed variance for gibbs vs ste with AdamW on theta (60 epochs, val only, signed, --qwd 0.1).
# b=8: gibbs tau 0.5 seeds 1/2, ste seed 2, gibbs tau 0.3 / 0.2, gibbs annealed 1.0 -> 0.2 (geometric);
# b=2/4: ste vs gibbs tau 0.5.  Run up to 3 at a time on one GPU.
P="python3 -m qc18.train --epochs 60 --test 0 --mode signed --qwd 0.1"; O=/tmp/${USER:-$(whoami)}/qc18/tau
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 0.5 --tau1 0.5 --seed 1 --out $O/s8_g05_s1
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 0.5 --tau1 0.5 --seed 2 --out $O/s8_g05_s2
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --seed 2 --out $O/s8_ste_s2
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 0.3 --tau1 0.3 --out $O/s8_g03
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 0.2 --tau1 0.2 --out $O/s8_g02
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 1.0 --tau1 0.2 --out $O/s8_gann
CUDA_VISIBLE_DEVICES=0 $P --b 2 --estimator ste --out $O/s2_ste_aw10
CUDA_VISIBLE_DEVICES=0 $P --b 2 --estimator gibbs --tau0 0.5 --tau1 0.5 --out $O/s2_g05_aw10
CUDA_VISIBLE_DEVICES=0 $P --b 4 --estimator ste --out $O/s4_ste_aw10
CUDA_VISIBLE_DEVICES=0 $P --b 4 --estimator gibbs --tau0 0.5 --tau1 0.5 --out $O/s4_g05_aw10
