"""Train QC (or dense) ResNet-18 on CIFAR-10.  One experiment per command, e.g.

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18.train --mode signed --b 8 --estimator gibbs --epochs 200

Fixed 45k/5k train/val split (qc.train.split, seed 0); best epoch selected on val; the test set is evaluated
once at the end (best-val checkpoint) only with --test 1.  QC val is the hard network (stored v) after BN
statistics are recalibrated on 10k unaugmented train images.  Writes best.pt, last.pt, metrics.json to --out.
Optimisers: SGD nesterov 0.9 (dense conv weights, BN, FC; wd only on dense conv / FC weights; linear warmup
then cosine) and Adam on theta (cosine, no wd).  tau annealed tau0 -> tau1 per epoch (--tau-sched).
Speed: GPU-resident data + augmentation, bf16 autocast for training (eval/recal fp32), channels_last,
torch.compile; dense and QC share the pipeline.
"""
import argparse
import getpass
import json
import math
import os
import time

import torch
import torch.nn.functional as F

from .data import augment, prep, split, test
from .model import QCResNet18
from .qcconv import QCConv2d

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


@torch.no_grad()
def accuracy(model, x, y, bs=1000):
    model.eval()
    c = sum((model(prep(x[i:i + bs])).argmax(1) == y[i:i + bs]).sum().item() for i in range(0, len(x), bs))
    return c / len(x)


@torch.no_grad()
def recal_bn(model, x, bs=500):
    """BN running statistics = exact average over x (train mode, fp32, no augmentation)."""
    bns = [m for m in model.modules() if isinstance(m, torch.nn.BatchNorm2d)]
    for m in bns:
        m.reset_running_stats()
        m.momentum = None
    model.train()
    for i in range(0, len(x), bs):
        model(prep(x[i:i + bs]))
    for m in bns:
        m.momentum = 0.1


def tau_at(a, ep):
    t = ep / max(1, a.epochs - 1)
    if a.tau_sched == "geometric":
        return a.tau0 * (a.tau1 / a.tau0) ** t
    return a.tau1 + (a.tau0 - a.tau1) * 0.5 * (1 + math.cos(math.pi * t))


def snapshot(model):
    return [c.v.clone() for c in model.qconvs()]


def flip_rate(model, prev):
    """Fraction of blocks whose hard v differs from the snapshot."""
    n = d = 0
    for c, p in zip(model.qconvs(), prev):
        d += (c.v != p).any(-1).sum().item()
        n += p.shape[0] * p.shape[1]
    return d / n if n else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="signed", choices=["dense", "signed", "unsigned"])
    ap.add_argument("--b", type=int, default=8)
    ap.add_argument("--estimator", default="ste", choices=["ste", "gibbs"])
    ap.add_argument("--tau0", type=float, default=1.0)
    ap.add_argument("--tau1", type=float, default=0.1)
    ap.add_argument("--tau-sched", default="geometric", choices=["geometric", "cosine"])
    ap.add_argument("--epochs", type=int, default=200)
    ap.add_argument("--bs", type=int, default=128)
    ap.add_argument("--lr", type=float, default=0.1, help="SGD lr (dense conv weights, BN, FC)")
    ap.add_argument("--wd", type=float, default=5e-4, help="SGD weight decay on dense conv / FC weights")
    ap.add_argument("--warmup", type=float, default=2, help="SGD linear warmup epochs")
    ap.add_argument("--qlr", type=float, default=1e-2, help="Adam lr for theta (unit-std init)")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--amp", type=int, default=1, help="bf16 autocast in training")
    ap.add_argument("--compile", type=int, default=1)
    ap.add_argument("--recal", type=int, default=10000, help="QC: train images for BN recalibration before val")
    ap.add_argument("--test", type=int, default=0, help="evaluate the test set once at the end")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    if not a.out:
        name = "dense" if a.mode == "dense" else f"{a.mode}_b{a.b}_{a.estimator}"
        a.out = f"/tmp/{getpass.getuser()}/qc18/runs/{name}_s{a.seed}"
    a.out = os.path.abspath(a.out)
    assert not (a.out + "/").startswith(REPO + "/"), "--out must be outside the repo"
    os.makedirs(a.out, exist_ok=True)
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False   # fp32 eval is fp32
    torch.backends.cudnn.benchmark = True
    torch.manual_seed(a.seed)
    dev = "cuda"

    (xtr, ytr), (xva, yva) = split(dev)
    model = QCResNet18(a.mode, a.b, a.estimator, a.tau0).to(dev).to(memory_format=torch.channels_last)
    qc = a.mode != "dense"

    theta = [p for n, p in model.named_parameters() if n.endswith("theta")]
    decay = [m.weight for m in model.modules() if isinstance(m, QCConv2d) and m.mode == "dense"] + [model.fc.weight]
    other = [p for p in model.parameters() if all(p is not q for q in theta + decay)]
    opts = [torch.optim.SGD([dict(params=decay, weight_decay=a.wd), dict(params=other, weight_decay=0.0)],
                            lr=a.lr, momentum=0.9, nesterov=True)]
    spe = len(xtr) // a.bs
    steps, warm = a.epochs * spe, int(min(a.warmup, a.epochs / 10) * spe)
    cos = lambda t: 0.5 * (1 + math.cos(math.pi * t / steps))
    sched = [torch.optim.lr_scheduler.LambdaLR(opts[0], lambda t: (t + 1) / warm if t < warm else cos(t))]
    if theta:
        opts.append(torch.optim.Adam(theta, lr=a.qlr, weight_decay=0.0))
        sched.append(torch.optim.lr_scheduler.LambdaLR(opts[1], cos))
    fwd = torch.compile(model) if a.compile else model

    def save(path, ep, va):
        torch.save(dict(args=vars(a), state=model.state_dict(), epoch=ep, val=va), path)

    best, hist = (-1.0, -1), []
    torch.cuda.reset_peak_memory_stats()
    for ep in range(a.epochs):
        tau = tau_at(a, ep)
        model.set_tau(tau)
        prev = snapshot(model)
        model.train()
        torch.cuda.synchronize()
        t0 = time.time()
        perm = torch.randperm(len(xtr), device=dev)
        tl = torch.zeros((), device=dev)
        tc = torch.zeros((), device=dev)
        for i in range(spe):
            idx = perm[i * a.bs:(i + 1) * a.bs]
            x, y = prep(augment(xtr[idx])), ytr[idx]
            with torch.autocast("cuda", torch.bfloat16, enabled=bool(a.amp)):
                out = fwd(x)
            loss = F.cross_entropy(out.float(), y)
            for o in opts:
                o.zero_grad(set_to_none=True)
            loss.backward()
            for o, s in zip(opts, sched):
                o.step()
                s.step()
            tl += loss.detach()
            tc += (out.argmax(1) == y).sum()
        torch.cuda.synchronize()
        ttrain = time.time() - t0
        model.refresh()                     # store hard v of the final theta of this epoch
        fr = flip_rate(model, prev)
        if qc:
            recal_bn(model, xtr[:a.recal])
        va = accuracy(model, xva, yva)
        dt = time.time() - t0
        hist.append(dict(epoch=ep, loss=tl.item() / spe, train_acc=tc.item() / (spe * a.bs), val=va,
                         sec_train=ttrain, sec=dt, flip=fr, tau=tau, lr=sched[0].get_last_lr()[0]))
        if va > best[0]:
            best = (va, ep)
            save(os.path.join(a.out, "best.pt"), ep, va)
        save(os.path.join(a.out, "last.pt"), ep, va)
        print(f"ep {ep:3d}  loss {hist[-1]['loss']:.4f}  train {100 * hist[-1]['train_acc']:.2f}  val {100 * va:.2f}  "
              f"best {100 * best[0]:.2f}@{best[1]}  flip {fr:.4f}  tau {tau:.3g}  {ttrain:.1f}s/{dt:.1f}s", flush=True)

    te = float("nan")
    if a.test:
        model.load_state_dict(torch.load(os.path.join(a.out, "best.pt"), map_location=dev)["state"])
        xte, yte = test(dev)
        te = accuracy(model, xte, yte)
    secs = sorted(h["sec_train"] for h in hist[1:]) or [hist[0]["sec_train"]]
    m = dict(args=vars(a), best_val=best[0], best_epoch=best[1], final_val=hist[-1]["val"], test=te,
             epoch_sec_median=secs[len(secs) // 2], peak_mem_gb=torch.cuda.max_memory_allocated() / 2 ** 30,
             history=hist)
    with open(os.path.join(a.out, "metrics.json"), "w") as f:
        json.dump(m, f, indent=1)
    print(f"RESULT {a.mode} b={a.b} {a.estimator}: best val {100 * best[0]:.2f} (epoch {best[1]})  "
          f"test {100 * te:.2f}  {m['epoch_sec_median']:.1f} s/epoch  peak {m['peak_mem_gb']:.2f} GB  -> {a.out}")


if __name__ == "__main__":
    main()
