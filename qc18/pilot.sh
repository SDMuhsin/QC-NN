# Pilot sweep (60 epochs, seed 0, val only).  Part A: signed b=8 estimators; part B: unsigned b=2 probe.
# Run up to 3 at a time on one GPU.  SGD qlr 7: one-epoch rms theta displacement matched to Adam qlr 1e-2.
P="python3 -m qc18.train --epochs 60 --seed 0 --test 0"; O=/tmp/${USER:-$(whoami)}/qc18/pilot
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --estimator ste --qlr 1e-2 --out $O/ste_q1e-2
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --estimator ste --qlr 1e-3 --out $O/ste_q1e-3
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --estimator gibbs --tau0 0.1 --tau1 0.1 --out $O/gibbs_t0.1
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --estimator gibbs --tau0 0.3 --tau1 0.3 --out $O/gibbs_t0.3
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --estimator gibbs --tau0 1.0 --tau1 1.0 --out $O/gibbs_t1
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --estimator gibbs --tau0 1.0 --tau1 0.03 --out $O/gibbs_anneal
CUDA_VISIBLE_DEVICES=0 $P --mode signed --b 8 --estimator gibbs --tau0 0.3 --tau1 0.3 --qopt sgd --qlr 7 --out $O/gibbs_t0.3_sgd
CUDA_VISIBLE_DEVICES=0 $P --mode dense --out $O/dense
CUDA_VISIBLE_DEVICES=0 $P --mode unsigned --b 2 --estimator gibbs --tau0 1.0 --tau1 0.1 --bn-sign 1 --out $O/u_bnsign
CUDA_VISIBLE_DEVICES=0 $P --mode unsigned --b 2 --estimator gibbs --tau0 1.0 --tau1 0.1 --bn-sign 1 --qinit-k 2 --out $O/u_bnsign_k2
