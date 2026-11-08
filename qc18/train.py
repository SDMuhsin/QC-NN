"""Train QC (or dense) ResNet-18 on CIFAR-10.  One experiment per command, e.g.

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18.train --mode signed --b 8 --estimator gibbs --epochs 200

Fixed 45k/5k train/val split (qc.train.split, seed 0); best epoch selected on val; the test set is evaluated
once at the end (best-val checkpoint) only with --test 1.  QC val is the hard network (stored v) after BN
statistics are recalibrated on 10k unaugmented train images.  Writes best.pt, last.pt, metrics.json to --out.
Optimisers: SGD nesterov 0.9 (dense conv weights, BN, FC; wd only on dense conv / FC weights; linear warmup
then cosine) and on theta (--qopt): AdamW (wd --qwd, default 0 = Adam) or SGD momentum 0.9 (cosine), or
sphere = Adam (no wd, cosine) with every block row of theta renormalised to unit RMS at init and after each step
(the hard projection is per-row scale-invariant, so the lr directly sets the angular step), or
sgdeq = "dense-equivalent" SGD: theta joins the main SGD (same nesterov, warmup, cosine) with lr = lr/b and
wd = wd*b (W = expand(theta) repeats each entry b times; scaled by --eq-lr / --eq-wd).  tau annealed tau0 -> tau1 per
epoch (--tau-sched).  Unsigned-mode init options: --bn-sign (random +-1 BN gamma), --qinit-k (sparse theta).
Diagnostics: --relax circ|top2 (real-weight relaxations, NOT QC; see qcconv); --kd A --kd-t T --teacher PATH
(loss = (1-A) CE + A T^2 KL(softmax(teacher/T) || softmax(student/T)), teacher a qc18 dense checkpoint, eval mode,
no grad, same augmented batch).
Homotopy (--homotopy gibbs|ramp, --h-frac F; QC, ste): over the first F of the training steps the training forward
moves from relaxed to hard, per step: gibbs = Gibbs mean E_p[v] with tau = tau0 * 0.01^(t/H) (exact Jacobian);
ramp = (1-lam) top2(theta)/alpha_r + lam (hard + STE), lam = t/H.  Then forward = hard + STE.  BN recalibration and
val always use the hard network; the best checkpoint is chosen only among epochs trained entirely in the hard phase.
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
from .diag.snap import Snapper
from .model import QCResNet18
from .qcconv import QCConv2d, sphere_

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
    ap.add_argument("--qlr", type=float, default=1e-2, help="theta lr (unit-std init)")
    ap.add_argument("--qopt", default="adam", choices=["adam", "sgd", "sgdeq", "sphere"],
                    help="theta optimiser (adam: AdamW wd --qwd; sgd: momentum 0.9; sgdeq: main SGD, lr/b, wd*b; "
                         "sphere: Adam, no wd, each block row renormalised to unit RMS after every step)")
    ap.add_argument("--qwd", type=float, default=0.0, help="adam: decoupled (AdamW) weight decay on theta")
    ap.add_argument("--eq-lr", type=float, default=1.0, help="sgdeq: theta lr = eq_lr * lr / b")
    ap.add_argument("--eq-wd", type=float, default=1.0, help="sgdeq: theta wd = eq_wd * wd * b")
    ap.add_argument("--qinit-k", type=int, default=0, help="QC init: only k random blocks per block row on (0: off)")
    ap.add_argument("--qinit-scale", default="unit", choices=["unit", "dense"],
                    help="theta init: unit std, or the projected Kaiming init at its dense scale")
    ap.add_argument("--bn-sign", type=int, default=0, help="init BN gamma with random +-1 signs (per channel)")
    ap.add_argument("--relax", default="none", choices=["none", "circ", "top2"],
                    help="diagnostic real-weight relaxation (not QC): circ = theta, top2 = theta on top-2 shifts")
    ap.add_argument("--homotopy", default="none", choices=["none", "gibbs", "ramp"],
                    help="training forward relaxed -> hard over the first --h-frac of training (see doc)")
    ap.add_argument("--h-frac", type=float, default=0.5, help="homotopy: fraction of training steps")
    ap.add_argument("--kd", type=float, default=0.0, help="distillation weight A (0: off)")
    ap.add_argument("--kd-t", type=float, default=4.0, help="distillation temperature T")
    ap.add_argument("--teacher", default="", help="qc18 dense checkpoint (best.pt) for --kd")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--amp", type=int, default=1, help="bf16 autocast in training")
    ap.add_argument("--compile", type=int, default=1)
    ap.add_argument("--recal", type=int, default=10000, help="QC: train images for BN recalibration before val")
    ap.add_argument("--test", type=int, default=0, help="evaluate the test set once at the end")
    ap.add_argument("--out", default="")
    ap.add_argument("--snap", type=int, default=0, help="save hard-v snapshots (qc18/diag/snap.py)")
    ap.add_argument("--snap-ckpt", default="10,30,60", help="--snap: full checkpoints at these epoch ends (1-based)")
    ap.add_argument("--snap-steps", default="10,30", help="--snap: v every --snap-every steps in these epochs")
    ap.add_argument("--snap-every", type=int, default=20)
    a = ap.parse_args()
    if not a.out:
        name = "dense" if a.mode == "dense" else f"{a.mode}_b{a.b}_{a.estimator}" + \
            ("" if a.relax == "none" else f"_{a.relax}")
        a.out = f"/tmp/{getpass.getuser()}/qc18/runs/{name}_s{a.seed}"
    a.out = os.path.abspath(a.out)
    assert not (a.out + "/").startswith(REPO + "/"), "--out must be outside the repo"
    os.makedirs(a.out, exist_ok=True)
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False   # fp32 eval is fp32
    torch.backends.cudnn.benchmark = True
    torch.manual_seed(a.seed)
    dev = "cuda"

    (xtr, ytr), (xva, yva) = split(dev)
    model = QCResNet18(a.mode, a.b, a.estimator, a.tau0, relax=a.relax, qinit_scale=a.qinit_scale,
                       homotopy=a.homotopy).to(dev).to(memory_format=torch.channels_last)
    qc = a.mode != "dense"
    if a.qinit_k:                           # sparse init: other blocks get theta = -|theta| (hard v = 0 there)
        with torch.no_grad():
            for c in model.qconvs():
                on = torch.zeros(c.theta.shape[:2], dtype=torch.bool, device=dev)
                on.scatter_(1, torch.rand(on.shape, device=dev).argsort(1)[:, :a.qinit_k], True)
                c.theta.copy_(torch.where(on[..., None], c.theta, -c.theta.abs()))
                c.refresh()
    if a.bn_sign:                           # signed per-output-channel scale (allowed by the QC definition)
        with torch.no_grad():
            for _, cb in model.convbns():
                cb.bn.weight.copy_(torch.randint(0, 2, cb.bn.weight.shape, device=dev) * 2.0 - 1)

    theta = [p for n, p in model.named_parameters() if n.endswith("theta")]
    if a.qopt == "sphere":                  # per-row unit RMS (hard weights unchanged: projection is scale-invariant)
        assert a.qwd == 0 and a.relax == "none", "--qopt sphere: no weight decay, QC (scale-invariant) forward only"
        for t in theta:
            sphere_(t)
    decay = [m.weight for m in model.modules() if isinstance(m, QCConv2d) and m.mode == "dense"] + [model.fc.weight]
    other = [p for p in model.parameters() if all(p is not q for q in theta + decay)]
    groups = [dict(params=decay, weight_decay=a.wd), dict(params=other, weight_decay=0.0)]
    if theta and a.qopt == "sgdeq":
        groups.append(dict(params=theta, lr=a.eq_lr * a.lr / a.b, weight_decay=a.eq_wd * a.wd * a.b))
    opts = [torch.optim.SGD(groups, lr=a.lr, momentum=0.9, nesterov=True)]
    spe = len(xtr) // a.bs
    steps, warm = a.epochs * spe, int(min(a.warmup, a.epochs / 10) * spe)
    cos = lambda t: 0.5 * (1 + math.cos(math.pi * t / steps))
    sched = [torch.optim.lr_scheduler.LambdaLR(opts[0], lambda t: (t + 1) / warm if t < warm else cos(t))]
    if theta and a.qopt != "sgdeq":
        opts.append(torch.optim.AdamW(theta, lr=a.qlr, weight_decay=a.qwd) if a.qopt in ("adam", "sphere") else
                    torch.optim.SGD(theta, lr=a.qlr, momentum=0.9))
        sched.append(torch.optim.lr_scheduler.LambdaLR(opts[1], cos))
    hsteps = int(round(a.h_frac * steps)) if a.homotopy != "none" else 0
    assert not hsteps or (qc and a.estimator == "ste" and a.relax == "none"), "--homotopy: QC, --estimator ste"

    def set_h(t):                           # homotopy state for global step t (off from step hsteps on)
        u = min(1.0, t / max(1, hsteps))
        h = a.tau0 * 0.01 ** u if a.homotopy == "gibbs" else u
        model.set_homotopy(t < hsteps, tau=h if a.homotopy == "gibbs" else None, lam=h if a.homotopy == "ramp" else None)
        return h                            # logged in the "tau" column (gibbs tau / ramp lam)

    fwd = torch.compile(model) if a.compile else model
    tfwd = None
    if a.kd:
        ck = torch.load(a.teacher, map_location=dev)
        assert ck["args"]["mode"] == "dense", "teacher must be a qc18 dense checkpoint"
        teacher = QCResNet18("dense").to(dev).to(memory_format=torch.channels_last)
        teacher.load_state_dict(ck["state"])
        teacher.eval().requires_grad_(False)
        tfwd = torch.compile(teacher) if a.compile else teacher
        print(f"teacher {a.teacher} (val {100 * ck['val']:.2f})", flush=True)

    def save(path, ep, va):
        torch.save(dict(args=vars(a), state=model.state_dict(), epoch=ep, val=va), path)

    best, hist = (-1.0, -1), []
    snap = Snapper(a, model)
    torch.cuda.reset_peak_memory_stats()
    for ep in range(a.epochs):
        tau = tau_at(a, ep)
        if not hsteps:
            model.set_tau(tau)
        prev = snapshot(model)
        model.train()
        torch.cuda.synchronize()
        t0 = time.time()
        perm = torch.randperm(len(xtr), device=dev)
        tl = torch.zeros((), device=dev)
        tc = torch.zeros((), device=dev)
        snap.epoch_start(ep)
        for i in range(spe):
            idx = perm[i * a.bs:(i + 1) * a.bs]
            x, y = prep(augment(xtr[idx])), ytr[idx]
            if hsteps:
                tau = set_h(ep * spe + i)
            with torch.autocast("cuda", torch.bfloat16, enabled=bool(a.amp)):
                out = fwd(x)
            loss = F.cross_entropy(out.float(), y)
            if tfwd is not None:
                with torch.no_grad(), torch.autocast("cuda", torch.bfloat16, enabled=bool(a.amp)):
                    tout = tfwd(x)
                T = a.kd_t
                kl = F.kl_div(F.log_softmax(out.float() / T, 1), F.log_softmax(tout.float() / T, 1),
                              reduction="batchmean", log_target=True)
                loss = (1 - a.kd) * loss + a.kd * T * T * kl
            for o in opts:
                o.zero_grad(set_to_none=True)
            loss.backward()
            for o, s in zip(opts, sched):
                o.step()
                s.step()
            if a.qopt == "sphere":
                for t in theta:
                    sphere_(t)
            snap.step(ep, i)
            tl += loss.detach()
            tc += (out.argmax(1) == y).sum()
        torch.cuda.synchronize()
        ttrain = time.time() - t0
        model.refresh()                     # store hard v of the final theta of this epoch
        hard_ep = ep * spe >= hsteps        # every step of this epoch used the hard forward
        if hsteps:
            model.set_homotopy(False)       # BN recalibration (train mode) on the hard network
        fr = flip_rate(model, prev)
        if qc:
            recal_bn(model, xtr[:a.recal])
        va = accuracy(model, xva, yva)
        dt = time.time() - t0
        hist.append(dict(epoch=ep, loss=tl.item() / spe, train_acc=tc.item() / (spe * a.bs), val=va,
                         sec_train=ttrain, sec=dt, flip=fr, tau=tau, hard=hard_ep, lr=sched[0].get_last_lr()[0]))
        if hard_ep and va > best[0]:
            best = (va, ep)
            save(os.path.join(a.out, "best.pt"), ep, va)
        save(os.path.join(a.out, "last.pt"), ep, va)
        snap.epoch_end(ep, lambda p: save(p, ep, va))
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
    print(f"RESULT {a.mode} b={a.b} {a.estimator}{'' if a.relax == 'none' else ' relax=' + a.relax}"
          f"{f' kd={a.kd}' if a.kd else ''}{f' homotopy={a.homotopy}' if a.homotopy != 'none' else ''}: best val {100 * best[0]:.2f} (epoch {best[1]})  "
          f"test {100 * te:.2f}  {m['epoch_sec_median']:.1f} s/epoch  peak {m['peak_mem_gb']:.2f} GB  -> {a.out}")


if __name__ == "__main__":
    main()
