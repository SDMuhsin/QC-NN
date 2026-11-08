# AdamW / init-scale sweep (60 epochs, val only).  The hard projection is scale-invariant in theta, so the angular
# update rate (lr x wd) should govern learning: sweep --qwd at b=8, check b=2/4, gibbs and the circ relaxation;
# sgdeq with --qinit-scale dense (theta at its natural dense Kaiming scale instead of unit std).
# Run up to 3 at a time on one GPU.
P="python3 -m qc18.train --epochs 60 --test 0 --mode signed"; O=/tmp/${USER:-$(whoami)}/qc18/aw
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qwd 0.02 --out $O/s8_aw02
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qwd 0.1 --out $O/s8_aw10
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qwd 0.2 --out $O/s8_aw20
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator gibbs --tau0 1.0 --tau1 1.0 --qwd 0.05 --out $O/s8_g1_aw05
CUDA_VISIBLE_DEVICES=0 $P --b 2 --estimator ste --qwd 0.05 --out $O/s2_aw05
CUDA_VISIBLE_DEVICES=0 $P --b 4 --estimator ste --qwd 0.05 --out $O/s4_aw05
CUDA_VISIBLE_DEVICES=0 $P --b 8 --relax circ --qwd 0.05 --out $O/rc8_aw05
CUDA_VISIBLE_DEVICES=0 $P --b 2 --relax circ --qopt sgdeq --qinit-scale dense --out $O/rc2_eq_di
CUDA_VISIBLE_DEVICES=0 $P --b 8 --estimator ste --qopt sgdeq --qinit-scale dense --out $O/s8_eq_di
