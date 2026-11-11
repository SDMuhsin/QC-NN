"""qc18.train on CIFAR-100 (see qc18b.c100).  Same options; default --out /tmp/$USER/qc18b/runs/<name>_s<seed>.
    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.train --mode signed --b 8 --epochs 200"""
import argparse
import getpass
import sys

import qc18.train

from . import c100

if __name__ == "__main__":
    c100.apply()
    if not any(s == "--out" or s.startswith("--out=") for s in sys.argv[1:]):
        p = argparse.ArgumentParser(add_help=False)
        for k, v in (("--mode", "signed"), ("--b", "8"), ("--estimator", "ste"), ("--relax", "none"), ("--seed", "0")):
            p.add_argument(k, default=v)
        a, _ = p.parse_known_args()
        name = "dense" if a.mode == "dense" else f"{a.mode}_b{a.b}_{a.estimator}" + \
            ("" if a.relax == "none" else f"_{a.relax}")
        sys.argv += ["--out", f"/tmp/{getpass.getuser()}/qc18b/runs/{name}_s{a.seed}"]
    qc18.train.main()
