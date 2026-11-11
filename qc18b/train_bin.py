"""qc18b.train (CIFAR-100 qc18.train) with binary activations (qc18b.binact) on every non-stem QCConv2d input.
Extra options (stripped before qc18.train parses argv):
  --binact 0|1  --ste clip|approx  --ste-w W  --bin-stem 0  --init CKPT (FP-act checkpoint, loaded before training;
  BinAct thresholds stay 0)  --log-every K (grad-flow jsonl -> <out>/gradflow.jsonl)
    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.train_bin --binact 1 --mode signed --b 8 --epochs 60 --out DIR"""
import argparse
import os
import sys

import torch

import qc18.train

from . import binact, c100

if __name__ == "__main__":
    p = argparse.ArgumentParser(allow_abbrev=False)
    p.add_argument("--binact", type=int, default=1)
    p.add_argument("--ste", default="clip", choices=["clip", "approx"])
    p.add_argument("--ste-w", type=float, default=1.0)
    p.add_argument("--bin-stem", type=int, default=0)
    p.add_argument("--init", default="")
    p.add_argument("--log-every", type=int, default=50)
    x, rest = p.parse_known_args()
    q = argparse.ArgumentParser(add_help=False, allow_abbrev=False)   # read (not stripped) the qc18.train options binarize needs
    q.add_argument("--out", default="")
    q.add_argument("--bs", type=int, default=128)
    q.add_argument("--compile", type=int, default=1)
    a, _ = q.parse_known_args(rest)
    assert a.out, "--out required"
    sys.argv = sys.argv[:1] + rest
    c100.apply()
    base = qc18.train.QCResNet18                   # c100's num_classes=100 factory

    def factory(*args, **kw):
        m = base(*args, **kw)
        if m.mode == "dense":                      # KD teacher (and --mode dense) stay plain
            return m
        os.makedirs(a.out, exist_ok=True)              # binact 0: FP activations, same logging forward
        m = binact.binarize(m, x.ste, x.ste_w, x.bin_stem, os.path.join(os.path.abspath(a.out), "gradflow.jsonl"),
                            x.log_every, 45000 // a.bs, bool(a.compile), act=bool(x.binact))
        if x.init:
            sd = torch.load(x.init, map_location="cpu")["state"]
            missing, unexpected = m.load_state_dict(sd, strict=False)
            assert not unexpected and all(k.endswith((".b1.t", ".b2.t")) for k in missing), (missing, unexpected)
            print(f"init {x.init}: {len(sd)} tensors, {len(missing)} BinAct thresholds left at 0", flush=True)
        print(f"binact={x.binact} ste={x.ste} w={x.ste_w} bin_stem={x.bin_stem}", flush=True)
        return m

    qc18.train.QCResNet18 = factory
    qc18.train.main()
