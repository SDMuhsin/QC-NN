# qc18b/ — CIFAR-100 QC ResNet-18 with 1-bit activations

Builds on `qc18/` (imported, never copied): same QC conv format (signed b = 8, ≤ 2 shifts per 8×8 block), same
trainer, now on CIFAR-100 and with every QC-conv input binarised to {0,1} by a learnable per-channel threshold.
Results, maths, ablations, failures: [RESULTS.md](RESULTS.md). Literature: [SURVEY.md](SURVEY.md).

| file | contents |
|---|---|
| `data.py`, `c100.py` | CIFAR-100 (env `QC18B_DATA`, default /workspace/PulseGrad/data/cifar-100-python), same 45k/5k split; runtime patch of `qc18.train` / `qc18.verify` |
| `train.py`, `verify.py`, `final.sh` | FP-activation pipeline (dense / s8 / s8kd) |
| `binact.py` | `BinAct`, `binarize()` and the activation / wiring options (see module docstring) |
| `train_bin.py` | binary-activation trainer (own flags, then `qc18.train.main`) |
| `bnopt.py`, `distill.py` | Adam for BN/thresholds; QC-teacher feature / logit / attention distillation |
| `verify_bin.py` | folded network, QC proof, integer b2 thresholds, fp64 check (`--test`: once) |
| `int_bin.py` | integer reference (int8 image, int32 acc, int16 stream, integer thresholds) |
| `opcount.py` | signed additions per block |
| `final_bin.sh` | final recipes `bin` (all 1-bit) and `e6` (block 6 at 8 bit) |
| `test_*.py` | unit tests (`python3 -m qc18b.test_binact`, `test_distill`, `test_bnopt`) |
| `diag/` | measurement scripts; tables in `diag/results/` |
| `results/` | `verify_*.txt`, `intbin_*.txt` of the final runs |

```bash
qc18b/final.sh train dense 0; qc18b/final.sh train s8kd 0      # teacher + init (FP activations)
qc18b/final_bin.sh train e6 0 && qc18b/final_bin.sh verify e6 0 && qc18b/final_bin.sh int e6 0
```
Runs go to `/tmp/$USER/qc18b/` (GPU 0). Reference repos for the survey: `./temp/` (gitignored).
