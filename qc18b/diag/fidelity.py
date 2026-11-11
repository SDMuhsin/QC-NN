"""STE fidelity on the qc18b (CIFAR-100) QC ResNet-18 (measurement only): does the autograd gradient (with the
model's own STEs) predict the actual change of the loss under small parameter perturbations?

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.diag.fidelity --ckpt BIN/last.pt --ckpt FP/last.pt --out JSON
    [--kinds bn,t,theta,fc] [--extra 0|1] [--full 0|1]   (split one run over processes; fidelity_table.py merges)

Model: rebuilt as qc18b.train_bin does (qc18.train args from the checkpoint, binact options from line 1 of the
run's train.log), state loaded, eager forward (model._net), train mode (BN batch statistics), fp32, TF32 off,
cuDNN deterministic, no autocast / compile.  Batch: 512 images of the 45k train split, torch.randperm(45000,
generator seed 0)[:512], no augmentation.  Loss = mean CE.
g = autograd gradient at p.  Per parameter group G and eps, N random directions d ~ Gaussian on G, ||d|| = 1,
delta = eps ||p_G|| d:  predicted = eps ||p_G|| <g_G, d>,  actual = (L(p + delta) - L(p - delta)) / 2.
Pearson corr(pred, actual) and OLS slope of actual ~ pred over the N directions.  theta groups also: fraction of
directions where hard(theta +- delta) differs from hard(theta) in any coefficient, and mean #coefficients changed.
Default groups: stem BN, per block BN of c1 / c2, BinAct t of b1 / b2, theta of c1 / c2, fc (--extra 1: also
stem theta, shortcut BN / theta).  Full network (non-theta parameters: BN, BinAct t, fc): d = -g / ||g||, delta = eps ||p|| d, central and forward
differences vs predicted = -eps ||p|| ||g||.
"""
import argparse
import json
import os
import time

import torch
import torch.nn.functional as F

import qc18.train
from qc18.model import QCResNet18
from qc18.qcconv import hard, row_alpha
from qc18b import binact, c100, data

EPS = (1e-3, 1e-2, 3e-2, 1e-1)
EPS_FULL = (1e-4, 3e-4, 1e-3, 3e-3, 1e-2, 3e-2, 1e-1)


def build(ckpt, dev):
    ck = torch.load(ckpt, map_location=dev, weights_only=False)
    a = ck["args"]
    with open(os.path.join(os.path.dirname(ckpt), "train.log")) as f:
        line = f.readline().split()
    o = dict(kv.split("=") for kv in line)
    m = QCResNet18(a["mode"], a["b"], a["estimator"], a["tau0"], num_classes=data.NUM_CLASSES, relax=a["relax"],
                   qinit_scale=a["qinit_scale"], homotopy=a["homotopy"]).to(dev).to(memory_format=torch.channels_last)
    m = binact.binarize(m, o["ste"], float(o["w"]), int(o["bin_stem"]), "", 0, 1, False, act=bool(int(o["binact"])),
                        k=float(o["K"]), t_train=int(o["t_train"]), preact=int(o["preact"]))
    m.load_state_dict(ck["state"])
    m.train()
    if a["homotopy"] != "none":
        m.set_homotopy(False)
    return m, a, o


def groups(m):
    """[(name, kind, [params])]; kinds bn / t / theta / fc."""
    G = [("stem.bn", "bn", [m.stem.bn.weight, m.stem.bn.bias]), ("stem.theta", "theta", [m.stem.conv.theta])]
    for i, blk in enumerate(m.blocks):
        for c in ("c1", "c2", "sc"):
            cb = getattr(blk, c)
            if cb is None:
                continue
            G.append((f"b{i}.{c}.bn", "bn", [cb.bn.weight, cb.bn.bias]))
        for bn in ("b1", "b2"):
            ba = getattr(blk, bn, None)
            if isinstance(ba, binact.BinAct):
                G.append((f"b{i}.{bn}.t", "t", [ba.t]))
        for c in ("c1", "c2", "sc"):
            cb = getattr(blk, c)
            if cb is not None:
                G.append((f"b{i}.{c}.theta", "theta", [cb.conv.theta]))
    G.append(("fc", "fc", [m.fc.weight, m.fc.bias]))
    return G


def owner(m):
    return {id(mod.theta): mod for mod in m.qconvs()}


def stats(p, a):
    p, a = torch.tensor(p, dtype=torch.float64), torch.tensor(a, dtype=torch.float64)
    pc, ac = p - p.mean(), a - a.mean()
    vp, va = (pc * pc).sum(), (ac * ac).sum()
    corr = (pc * ac).sum() / (vp * va).sqrt() if vp > 0 and va > 0 else float("nan")
    slope = (pc * ac).sum() / vp if vp > 0 else float("nan")
    return float(corr), float(slope), float(p.abs().mean()), float(a.abs().mean())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", action="append", required=True)
    ap.add_argument("--n", type=int, default=64)
    ap.add_argument("--bs", type=int, default=512)
    ap.add_argument("--kinds", default="bn,t,theta,fc", help="group kinds measured by this process")
    ap.add_argument("--extra", type=int, default=0, help="1: also stem.theta and the shortcut (sc) groups")
    ap.add_argument("--full", type=int, default=1, help="full-network -g check")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False
    dev = "cuda"
    c100.apply()
    (xtr, ytr), _ = data.split(dev)
    idx = torch.randperm(len(xtr), generator=torch.Generator().manual_seed(0))[:a.bs].to(dev)
    x, y = qc18.train.prep(xtr[idx]), ytr[idx]
    res = {}
    for ck in a.ckpt:
        t0 = time.time()
        m, args, o = build(ck, dev)
        own = owner(m)
        loss = lambda: F.cross_entropy(m._net(x), y)
        m.zero_grad(set_to_none=True)
        L0 = loss()
        L0.backward()
        with torch.no_grad():
            L0b = loss().item()
        r = dict(ckpt=ck, binact_opts=o, L0=L0.item(), L0_repeat=L0b, groups=[])
        print(f"{ck}: L0 {L0.item():.6f} repeat {L0b:.6f}", flush=True)
        gen = torch.Generator(device=dev).manual_seed(1)
        with torch.no_grad():
            for name, kind, ps in groups(m):
                if kind not in a.kinds.split(",") or (not a.extra and (name == "stem.theta" or ".sc." in name)):
                    continue
                gs = [p.grad.detach().clone() for p in ps]
                p0 = [p.detach().clone() for p in ps]
                pn = torch.sqrt(sum((q.double() ** 2).sum() for q in p0)).item()
                gn = torch.sqrt(sum((q.double() ** 2).sum() for q in gs)).item()
                if kind == "theta":
                    conv = own[id(ps[0])]
                    v0 = hard(p0[0], row_alpha(p0[0]), conv.signed)
                rows = []
                for eps in EPS:
                    pred, act, chg, nchg = [], [], 0, 0.0
                    for _ in range(a.n):
                        d = [torch.randn(q.shape, device=dev, generator=gen) for q in p0]
                        dn = torch.sqrt(sum((q.double() ** 2).sum() for q in d)).item()
                        s = eps * pn / dn
                        pred.append(s * sum((gg.double() * dd.double()).sum() for gg, dd in zip(gs, d)).item())
                        Ls, any_chg = [], False
                        for sg in (1, -1):
                            for p, q, dd in zip(ps, p0, d):
                                p.copy_(q + sg * s * dd)
                            Ls.append(loss().item())
                            if kind == "theta":
                                nv = (hard(ps[0], row_alpha(ps[0]), conv.signed) != v0).sum().item()
                                nchg += nv / 2          # mean over the two signs
                                any_chg = any_chg or nv > 0
                        act.append((Ls[0] - Ls[1]) / 2)
                        chg += int(any_chg)
                        for p, q in zip(ps, p0):
                            p.copy_(q)
                    c, sl, mp, ma = stats(pred, act)
                    row = dict(eps=eps, corr=c, slope=sl, mean_abs_pred=mp, mean_abs_act=ma)
                    if kind == "theta":
                        row.update(frac_v_changed=chg / a.n, mean_n_v_changed=nchg / a.n, n_coef=v0.numel())
                    rows.append(row)
                r["groups"].append(dict(name=name, kind=kind, p_norm=pn, g_norm=gn, rows=rows))
                print(name, kind, " ".join(f"{q['eps']:g}:{q['corr']:.3f}/{q['slope']:.3f}" +
                                           (f"/v{q['frac_v_changed']:.2f}" if kind == "theta" else "") for q in rows),
                      f"{time.time() - t0:.0f}s", flush=True)
        if a.full:
            with torch.no_grad():  # full network, non-theta parameters, d = -g
                ps = [p for p in m.parameters() if p.grad is not None and all(p is not c.theta for c in m.qconvs())]
                p0 = [p.detach().clone() for p in ps]
                gs = [p.grad.detach().clone() for p in ps]
                pn = torch.sqrt(sum((q.double() ** 2).sum() for q in p0)).item()
                gn = torch.sqrt(sum((q.double() ** 2).sum() for q in gs)).item()
                full = []
                for eps in EPS_FULL:
                    s = eps * pn / gn
                    Ls = []
                    for sg in (1, -1):
                        for p, q, gg in zip(ps, p0, gs):
                            p.copy_(q - sg * s * gg)
                        Ls.append(loss().item())
                    for p, q in zip(ps, p0):
                        p.copy_(q)
                    full.append(dict(eps=eps, pred=-eps * pn * gn, central=(Ls[0] - Ls[1]) / 2, forward=Ls[0] - L0.item()))
                    print("full", full[-1], flush=True)
                r["full"] = dict(n_params=sum(q.numel() for q in p0), p_norm=pn, g_norm=gn, rows=full)
        res[ck] = r
        del m
        torch.cuda.empty_cache()
    with open(a.out, "w") as f:
        json.dump(res, f, indent=1)


if __name__ == "__main__":
    main()
