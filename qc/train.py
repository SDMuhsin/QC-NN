"""Train QC (or dense baseline) ResNet-8 on CIFAR-10.  One command per experiment:

    CUDA_VISIBLE_DEVICES=0 python -m qc.train --mode unsigned --b 8 --epochs 200 --out /tmp/$USER/qc/runs/NAME

Fixed 45k/5k train/val split (seed 0); best epoch selected by val accuracy; the test set is evaluated
once, at the end, with the best-val checkpoint (--test 0 skips it).  Writes best.pt and metrics.json into --out.

--method staged (default; see qc.layers), epochs split by --stages fA,fB,fC:
  A  real block-circulant coefficients, all b shifts;
  B  shifts pruned per block by magnitude, b -> topk linearly over the B epochs (nested), mask then frozen;
  C  lam ramps 0 -> 1 over the first --ramp fraction of C (real -> hard 0/1 or -1/0/1, STE on the real
     coefficients), then hard.  Only hard (lam = 1) epochs are checkpoint candidates; their BN statistics are recalibrated on 10k train
     images before val.
--method qat (see qc.layers): hard coefficients in the forward pass from the first step, STE on latent
  real coefficients trained with Adam (--qat-lr, cosine -> 0, no weight decay); BN/FC keep SGD.  The top-k
  shift mask is recomputed from the latent magnitudes every step during the first --freeze fraction of
  the epochs, then frozen.  Every epoch is a checkpoint candidate.
--teacher PATH: distill (--kd, --kd-t) from a dense qc.train checkpoint instead of the Keras model (which
  was trained on all 50k train images, i.e. it has seen our val split).
One SGD + cosine schedule over the whole run; at the end the BN statistics of the best checkpoint are
recalibrated on the (unaugmented) train split and kept if val does not drop.
"""
import argparse
import json
import os
import time

import numpy as np
import torch
import torch.nn.functional as F

from nn.model.data import H5_PATH, test_set, train_set
from nn.model.resnet8 import CONVS, ResNet8, load_h5

from .model import QCResNet8


def split(dev):
    x, y = train_set()
    p = np.random.default_rng(0).permutation(len(x))
    t = lambda a: torch.as_tensor(a, device=dev)
    return (t(x[p[:45000]]), t(y[p[:45000]])), (t(x[p[45000:]]), t(y[p[45000:]]))


def augment(x):
    """Random crop (zero pad 4) + horizontal flip, on GPU, NHWC uint8."""
    n = len(x)
    xp = F.pad(x, (0, 0, 4, 4, 4, 4))
    oy, ox = torch.randint(0, 9, (2, n, 1), device=x.device)
    r = torch.arange(32, device=x.device)
    rows, cols = oy + r, ox + r
    flip = torch.rand(n, 1, device=x.device) < 0.5
    cols = torch.where(flip, cols.flip(1), cols)
    return xp[torch.arange(n, device=x.device)[:, None, None], rows[:, :, None], cols[:, None, :]]


@torch.no_grad()
def recal_bn(model, x, bs=500):
    """Recompute BN running statistics as the exact average over x (train mode, no augmentation)."""
    bns = [m for m in model.modules() if isinstance(m, torch.nn.BatchNorm2d)]
    for m in bns:
        m.reset_running_stats()
        m.momentum = None
    model.train()
    for i in range(0, len(x), bs):
        model(x[i:i + bs])
    for m in bns:
        m.momentum = 0.1


def stage(a, ep, model):
    """Apply the staged schedule at the start of epoch ep; returns (k shifts kept, lam)."""
    E = a.epochs
    fa, fb, _ = (float(f) for f in a.stages.split(","))
    ea, eb = round(fa * E), round(fb * E)
    lam, ks = 0.0, []
    if ep >= ea + eb:
        lam = min(1.0, (ep - ea - eb + 1) / max(1.0, a.ramp * (E - ea - eb)))
    for m in model.conv.values():     # per-conv block size m.b
        k = m.b
        if ea <= ep < ea + eb:
            k = max(a.topk, -(-(m.b * (eb - (ep - ea + 1)) + a.topk * (ep - ea + 1)) // eb))   # b -> topk linearly
        elif ep >= ea + eb:
            k = a.topk
        if k < m.b:
            m.prune_to(k)
        m.lam.fill_(lam)
        ks.append(min(k, m.b))
    return max(ks), lam


@torch.no_grad()
def accuracy(model, x, y, bs=2500, amp=False):
    model.eval()
    with torch.autocast("cuda", torch.bfloat16, enabled=amp):
        c = sum((model(x[i:i + bs]).argmax(1) == y[i:i + bs]).sum().item() for i in range(0, len(x), bs))
    return c / len(x)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="unsigned", choices=["unsigned", "signed", "dense"])
    ap.add_argument("--b", default="8", help="block size, or one per conv in CONVS order, e.g. 4,4,4,8,8,8,8,8,8")
    ap.add_argument("--topk", type=int, default=2)
    ap.add_argument("--view", default="hwc", choices=["hwc", "chw"])
    ap.add_argument("--method", default="staged", choices=["staged", "ste", "qat"], help="see qc.layers")
    ap.add_argument("--stages", default="0.3,0.3,0.4", help="staged: epoch fractions of stages A,B,C")
    ap.add_argument("--ramp", type=float, default=0.25, help="staged: fraction of stage C ramping lam 0->1")
    ap.add_argument("--thr", type=float, default=0.0, help="staged: q=0 below thr * mean|kept coef| of the block row")
    ap.add_argument("--coef-lr", type=float, default=1.0, help="staged: lr multiplier of the coefficients")
    ap.add_argument("--qat-lr", type=float, default=1e-3, help="qat: Adam lr of the latent coefficients")
    ap.add_argument("--freeze", type=float, default=0.5, help="qat: fraction of epochs with a per-step top-k mask")
    ap.add_argument("--ste-clip", type=float, default=0.0, help="qat: no gradient where |coef| > clip*alpha (0 = off)")
    ap.add_argument("--clamp0", type=int, default=0, help="qat unsigned: project latent coef to >= 0 (as staged)")
    ap.add_argument("--teacher", default="", help="dense qc.train checkpoint used as KD teacher")
    ap.add_argument("--test", type=int, default=1, help="evaluate the test set at the end")
    ap.add_argument("--init", default="random", help="random | dense (Keras .h5) | PATH of a qc.train checkpoint "
                    "(dense: projected onto block-circulant; QC: copied)")
    ap.add_argument("--soft", type=float, default=0.0, help="qat: first fraction of epochs with real coefficients "
                    "(two-stage; the lr schedules restart at the switch to hard)")
    ap.add_argument("--width", type=int, default=1, help="conv channel multiplier (capacity probe, not ResNet-8)")
    ap.add_argument("--epochs", type=int, default=200)
    ap.add_argument("--bs", type=int, default=128)
    ap.add_argument("--lr", type=float, default=0.1)
    ap.add_argument("--wd", type=float, default=5e-4)
    ap.add_argument("--score-lr", type=float, default=1e-3, help="Adam lr for the QC scores")
    ap.add_argument("--kd", type=float, default=0.0, help="distillation weight alpha (0 = off)")
    ap.add_argument("--kd-t", type=float, default=4.0)
    ap.add_argument("--amp", type=int, default=None, help="bf16 autocast (default: dense only; QC needs fp32)")
    ap.add_argument("--compile", type=int, default=1, help="torch.compile the training forward")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    a.b = [int(v) for v in a.b.split(",")] if "," in a.b else int(a.b)
    assert not os.path.abspath(a.out).startswith(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    os.makedirs(a.out, exist_ok=True)
    # QC convs sum +-1 * raw activations and BN then removes a large mean: bf16/TF32 rounding of the
    # conv output destroys the signal (bf16 eval differed from fp64 by up to 18 % accuracy), so fp32.
    a.amp = (a.mode == "dense") if a.amp is None else bool(a.amp)
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = a.amp
    torch.manual_seed(a.seed)
    dev = "cuda"

    (xtr, ytr), (xva, yva) = split(dev)
    model = QCResNet8(a.mode, a.b, a.topk, a.view, a.method, a.thr, a.width).to(dev)
    assert a.width == 1 or a.init in ("random",), "--init needs width 1"
    staged = a.mode != "dense" and a.method == "staged"
    qat = a.mode != "dense" and a.method == "qat"
    if qat:
        for m in model.conv.values():
            m.lam.fill_(1.0)
            m.clip = a.ste_clip
    if a.init == "dense" or (a.kd > 0 and not a.teacher):
        params = load_h5(H5_PATH)
    if a.init not in ("random", "dense"):
        st = torch.load(a.init, map_location=dev)["state"]
        if a.mode != "dense" and "conv.conv0.weight" in st:
            for n, *_ in CONVS:
                model.conv[n].init_from_dense(st.pop(f"conv.{n}.weight").cpu())
        st = {k: v for k, v in st.items() if not k.endswith((".lam", ".mask"))}
        print("init from", a.init, model.load_state_dict(st, strict=False))
    if a.init == "dense":
        for n, *_ in CONVS:
            if a.mode == "dense":
                model.conv[n].weight.data.copy_(torch.as_tensor(params[n][0]))
            else:
                model.conv[n].init_from_dense(params[n][0])
    teacher = ResNet8(params, torch.float32, dev) if a.kd > 0 and not a.teacher else None
    if a.kd > 0 and a.teacher:
        tck = torch.load(a.teacher, map_location=dev)
        tm = QCResNet8("dense").to(dev)
        tm.load_state_dict(tck["state"])
        tm.eval()
        teacher = type("T", (), dict(forward=lambda self, x: tm(x)))()

    # QC scores only matter through their ranking/sign and their gradients are tiny next to their
    # scale (BN after +-1 weights), so they get Adam without weight decay; the rest is SGD.
    scores = [p for n, p in model.named_parameters() if n.endswith("scores")]
    rest = [p for n, p in model.named_parameters() if not n.endswith("scores")]
    coef = [p for n, p in model.named_parameters() if n.endswith("coef")]
    rest = [p for p in rest if all(p is not q for q in coef)]
    groups = [dict(params=rest)] + ([dict(params=coef, lr=a.lr * a.coef_lr)] if coef and not qat else [])
    opts = [torch.optim.SGD(groups, lr=a.lr, momentum=0.9, nesterov=True, weight_decay=a.wd)]
    if qat:
        opts.append(torch.optim.Adam(coef, lr=a.qat_lr, weight_decay=0.0))
    if scores:
        opts.append(torch.optim.Adam(scores, lr=a.score_lr))
    steps = a.epochs * (len(xtr) // a.bs)
    s1 = round(a.soft * a.epochs) * (len(xtr) // a.bs) if qat else 0
    cos = lambda t: 0.5 * (1 + np.cos(np.pi * (t / s1 if t < s1 else (t - s1) / (steps - s1))))
    scheds = [torch.optim.lr_scheduler.LambdaLR(o, cos) for o in opts] if s1 else \
        [torch.optim.lr_scheduler.CosineAnnealingLR(o, steps) for o in opts]
    fwd = torch.compile(model) if a.compile else model
    best, hist = (-1.0, 0), []
    k, lam = None, 1.0
    for ep in range(a.epochs):
        if staged:
            k, lam = stage(a, ep, model)
        if qat:
            lam = float(ep >= round(a.soft * a.epochs))
            for m in model.conv.values():
                m.lam.fill_(lam)
        model.train()
        t0 = time.time()
        perm = torch.randperm(len(xtr), device=dev)
        tl = torch.zeros((), device=dev)
        for i in range(len(xtr) // a.bs):
            idx = perm[i * a.bs:(i + 1) * a.bs]
            x, y = augment(xtr[idx]), ytr[idx]
            if qat and ep < round(a.freeze * a.epochs):
                for m in model.conv.values():
                    m.topk_mask()
            with torch.autocast("cuda", torch.bfloat16, enabled=a.amp):
                out = fwd(x)
            loss = F.cross_entropy(out.float(), y)
            if teacher is not None:
                with torch.no_grad(), torch.autocast("cuda", torch.bfloat16, enabled=bool(a.teacher)):
                    tlog = teacher.forward(x.float()).float()
                kl = F.kl_div(F.log_softmax(out.float() / a.kd_t, 1), F.softmax(tlog / a.kd_t, 1),
                              reduction="batchmean") * a.kd_t ** 2
                loss = (1 - a.kd) * loss + a.kd * kl
            for o in opts:
                o.zero_grad(set_to_none=True)
            loss.backward()
            for o, sc in zip(opts, scheds):
                o.step()
                sc.step()
            if (staged or (qat and a.clamp0)) and a.mode == "unsigned":
                with torch.no_grad():
                    for m in model.conv.values():
                        m.coef.clamp_(min=0)
            tl += loss.detach()
        if (staged or qat) and lam >= 1:     # running stats lag the flipping hard weights: recalibrate before val
            recal_bn(model, xtr[:10000])
        va = accuracy(model, xva, yva, amp=a.amp)
        dt = time.time() - t0
        hist.append(dict(epoch=ep, loss=tl.item() / (i + 1), val=va, sec=dt))
        hist[-1].update(k=k, lam=lam)
        if lam >= 1 and va > best[0]:
            best = (va, ep)
            torch.save(dict(args=vars(a), state=model.state_dict(), epoch=ep, val=va), os.path.join(a.out, "best.pt"))
        print(f"ep {ep:3d}  k {k}  lam {lam:.2f}  loss {hist[-1]['loss']:.4f}  val {100 * va:.2f}  best {100 * best[0]:.2f}@{best[1]}  {dt:.1f}s",
              flush=True)

    if best[0] < 0:     # no hard epoch (e.g. --stages 1,0,0 diagnostics)
        print(f"RESULT no QC checkpoint; last val {100 * hist[-1]['val']:.2f}")
        return
    ck = torch.load(os.path.join(a.out, "best.pt"), map_location=dev)
    model.load_state_dict(ck["state"])
    val_pre = None
    if staged or qat:
        val_pre = best[0]
        recal_bn(model, xtr)
        va = accuracy(model, xva, yva, amp=a.amp)
        print(f"BN recalibration: val {100 * val_pre:.2f} -> {100 * va:.2f}")
        if va >= val_pre:
            best = (va, best[1])
            torch.save(dict(args=vars(a), state=model.state_dict(), epoch=best[1], val=va), os.path.join(a.out, "best.pt"))
        else:
            model.load_state_dict(ck["state"])
    xte, yte = (torch.as_tensor(t, device=dev) for t in test_set())
    te = accuracy(model, xte, yte, amp=a.amp) if a.test else float("nan")
    fv = ft = float("nan")
    if a.mode != "dense":     # report the exact folded QC network (fp64, as qc.verify)
        from .verify import folded_accuracy, load
        fm = load(torch.load(os.path.join(a.out, "best.pt"), map_location="cpu"))
        fv = folded_accuracy(fm, xva, yva)
        ft = folded_accuracy(fm, xte, yte) if a.test else float("nan")
    m = dict(args=vars(a), best_val=best[0], best_epoch=best[1], test=te, val_before_recal=val_pre, folded_val=fv, folded_test=ft, final_val=hist[-1]["val"],
             epoch_sec=float(np.median([h["sec"] for h in hist])), history=hist)
    with open(os.path.join(a.out, "metrics.json"), "w") as f:
        json.dump(m, f, indent=1)
    print(f"RESULT {a.mode} b={a.b}: best val {100 * best[0]:.2f} (epoch {best[1]})  test {100 * te:.2f}  "
          f"folded fp64: val {100 * fv:.2f} test {100 * ft:.2f}")


if __name__ == "__main__":
    main()
