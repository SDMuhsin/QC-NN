"""Activation measurements on the qc18b (CIFAR-100) QC ResNet-18 conv inputs (measurement only).

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.diag.actmeas --ckpt CKPT --tag s8kd [--m 1234] --out FILE

The 20 conv inputs are captured with forward pre-hooks on the QCConv2d modules (stem input = normalised image;
c1 / sc input = block input; c2 input = relu(bn(c1))).  fp32, TF32 off, eval mode unless stated.
M1  input statistics on the 5k val split.
M2  binarise one conv input x_b = a * 1[x > t_c]; (i) t=0, per-tensor LS a; (ii) per-channel (t_c, a_c) LS-optimal
    over 64 channel quantiles (levels (k+0.5)/64); (iii) t_c of (ii), one per-tensor LS a.  Fitted and evaluated on
    val.  Conv output (pre-BN) relative error, cosine, and the error after removing per-output-channel means.
M3  val accuracy with variant (iii) inputs (t_c, a fitted on the 10k train images used for BN recalibration, on
    the unmodified net), BN recalibrated with qc18.train.recal_bn on train[:10000] with the hooks active.
    (a) one conv at a time, (b) the 19 non-stem convs, (c) all 20; (b)/(c) also with a sequential refit
    (conv i fitted on the net with convs < i binarised and BN recalibrated).
M4  BN train mode, one 500-image train batch (train[:500], no aug), CE loss; gradient w.r.t. each conv input through
    that conv only (the pre-hook feeds the conv x + z, z a zero leaf; g = dL/dz); window fraction |x - t_c| < std_c with t_c from (ii)
    (val fit) and std_c the per-channel std of x on that batch.
"""
import argparse
import copy
import json
import time

import torch
import torch.nn.functional as F

import qc18.train
import qc18.verify
from qc18b import c100

NQ = 64


def names_convs(model):
    return [(n, cb.conv) for n, cb in model.convbns()]


@torch.no_grad()
def capture(model, conv, x, bs=500):
    """Input of conv for all images x (uint8 NHWC), model in its current mode -> [N, C, H, W] fp32 contiguous."""
    out = []
    h = conv.register_forward_pre_hook(lambda m, inp: out.append(inp[0].detach().contiguous()))
    try:
        for i in range(0, len(x), bs):
            model(qc18.train.prep(x[i:i + bs]))
    finally:
        h.remove()
    return torch.cat(out)


def chan_rows(X):
    return X.transpose(0, 1).reshape(X.shape[1], -1)


@torch.no_grad()
def fit(X):
    """-> dict(t0_a, t [C], ac [C], a3) for variants (i), (ii), (iii)."""
    Xc = chan_rows(X)
    C, n = Xc.shape
    lev = ((torch.arange(NQ, device=X.device) + 0.5) / NQ * n).long().clamp(max=n - 1)
    q = torch.empty(C, NQ, device=X.device)
    for c0 in range(0, C, 8):
        q[c0:c0 + 8] = Xc[c0:c0 + 8].sort(dim=1).values[:, lev]
    ss = (Xc * Xc).sum(1, dtype=torch.float64)
    best = torch.full((C,), float("inf"), dtype=torch.float64, device=X.device)
    t = torch.zeros(C, device=X.device)
    S_b = torch.zeros(C, dtype=torch.float64, device=X.device)
    n_b = torch.zeros(C, dtype=torch.float64, device=X.device)
    for k in range(NQ):
        m = Xc > q[:, k:k + 1]
        S = torch.where(m, Xc, 0).sum(1, dtype=torch.float64)
        cnt = m.sum(1).double()
        err = ss - torch.where(cnt > 0, S * S / cnt.clamp(min=1), 0)
        upd = err < best
        best = torch.where(upd, err, best)
        t = torch.where(upd, q[:, k], t)
        S_b, n_b = torch.where(upd, S, S_b), torch.where(upd, cnt, n_b)
    ac = torch.where(n_b > 0, S_b / n_b.clamp(min=1), 0).float()
    a3 = (S_b.sum() / n_b.sum()).item()
    pos = Xc > 0
    t0_a = (torch.where(pos, Xc, 0).sum(dtype=torch.float64) / pos.sum()).item()
    return dict(t0_a=t0_a, t=t, ac=ac, a3=a3)


def binarize(x, t, a):
    """a * 1[x > t]; t scalar or [C], a scalar or [C]."""
    sh = (1, -1, 1, 1)
    tt = t.view(sh) if torch.is_tensor(t) else t
    aa = a.view(sh) if torch.is_tensor(a) else a
    return (x > tt).to(x.dtype) * aa


def variants(f):
    return {"i": (0.0, f["t0_a"]), "ii": (f["t"], f["ac"]), "iii": (f["t"], f["a3"])}


@torch.no_grad()
def m1(X):
    Xc = chan_rows(X)
    flat = X.reshape(-1)
    s = flat.sort().values
    n = flat.numel()
    qs = [s[min(n - 1, int(p * n))].item() for p in (0.5, 0.9, 0.99)] + [s[-1].item()]
    del s
    cm, cz = Xc.mean(1), (Xc == 0).double().mean(1)
    spread = lambda v: (v.min().item(), v.median().item(), v.max().item())
    return dict(zero=(flat == 0).double().mean().item(), p50=qs[0], p90=qs[1], p99=qs[2], max=qs[3],
                cmean=spread(cm), czero=spread(cz))


@torch.no_grad()
def m2(conv, X, f, bs=250):
    res = {}
    for v, (t, a) in variants(f).items():
        acc = dict(dd=0.0, yy=0.0, yb=0.0, bb=0.0, xin=0.0, xx=0.0)
        Cout = None
        for i in range(0, len(X), bs):
            x = X[i:i + bs]
            xb = binarize(x, t, a)
            y, z = conv(x).double(), conv(xb).double()
            d = z - y
            acc["dd"] += (d * d).sum().item()
            acc["yy"] += (y * y).sum().item()
            acc["yb"] += (y * z).sum().item()
            acc["bb"] += (z * z).sum().item()
            acc["xin"] += ((xb - x).double() ** 2).sum().item()
            acc["xx"] += (x.double() ** 2).sum().item()
            sd, sy = d.sum((0, 2, 3)), y.sum((0, 2, 3))
            if Cout is None:
                Cout, sdd, syy, npix = d.shape[1], sd, sy, 0
            else:
                sdd, syy = sdd + sd, syy + sy
            npix += d.shape[0] * d.shape[2] * d.shape[3]
        dd_c = acc["dd"] - (sdd * sdd).sum().item() / npix
        yy_c = acc["yy"] - (syy * syy).sum().item() / npix
        res[v] = dict(rel=(acc["dd"] / acc["yy"]) ** 0.5, cos=acc["yb"] / (acc["yy"] * acc["bb"]) ** 0.5,
                      relc=(dd_c / yy_c) ** 0.5, relin=(acc["xin"] / acc["xx"]) ** 0.5)
    return res


class Binz:
    """Forward pre-hooks a * 1[x > t_c] on a set of convs."""

    def __init__(self, convs, fits):
        self.hs = []
        for c, f in zip(convs, fits):
            t, a = f["t"], f["a3"]
            self.hs.append(c.register_forward_pre_hook(lambda m, inp, t=t, a=a: (binarize(inp[0], t, a),)))

    def remove(self):
        for h in self.hs:
            h.remove()


def eval_bin(model, state, convs, fits, xr, xv, yv):
    model.load_state_dict(state)
    b = Binz(convs, fits)
    try:
        qc18.train.recal_bn(model, xr)
        return qc18.train.accuracy(model, xv, yv)
    finally:
        b.remove()
        model.load_state_dict(state)
        model.eval()


def m3(model, state, nc, xr, xv, yv, log):
    convs = [c for _, c in nc]
    fits_tr = [fit(capture(model, c, xr)) for c in convs]
    torch.cuda.empty_cache()
    out = dict(base=qc18.train.accuracy(model, xv, yv))
    model.load_state_dict(state)
    qc18.train.recal_bn(model, xr)
    out["recal_only"] = qc18.train.accuracy(model, xv, yv)
    model.load_state_dict(state)
    model.eval()
    log(f"M3 base {out['base']:.4f} recal-only {out['recal_only']:.4f}")
    out["a"] = []
    for i, (n, c) in enumerate(nc):
        acc = eval_bin(model, state, [c], [fits_tr[i]], xr, xv, yv)
        out["a"].append(acc)
        log(f"M3a {n} {acc:.4f}")
    out["b"] = eval_bin(model, state, convs[1:], fits_tr[1:], xr, xv, yv)
    out["c"] = eval_bin(model, state, convs, fits_tr, xr, xv, yv)
    log(f"M3b {out['b']:.4f} M3c {out['c']:.4f}")
    # sequential refit
    for key, start in (("b_seq", 1), ("c_seq", 0)):
        fits = []
        for i in range(start, len(convs)):
            model.load_state_dict(state)
            b = Binz(convs[start:i], fits)
            try:
                if fits:
                    qc18.train.recal_bn(model, xr)
                model.eval()
                fits.append(fit(capture(model, convs[i], xr)))
            finally:
                b.remove()
            torch.cuda.empty_cache()
        out[key] = eval_bin(model, state, convs[start:], fits, xr, xv, yv)
        log(f"M3 {key} {out[key]:.4f}")
    model.load_state_dict(state)
    model.eval()
    return out


def m4(model, state, nc, xb, yb, fits_val):
    model.load_state_dict(state)
    model.train()
    xs = {}

    def mk(n):
        def hook(m, inp):
            z = torch.zeros_like(inp[0], requires_grad=True)   # dL/dz = dL/dx through this conv only
            xs[n] = (inp[0].detach(), z)
            return (inp[0] + z,)
        return hook

    hs = [c.register_forward_pre_hook(mk(n)) for n, c in nc]
    try:
        loss = F.cross_entropy(model(qc18.train.prep(xb)), yb)
        loss.backward()
    finally:
        for h in hs:
            h.remove()
    out = []
    for (n, _), f in zip(nc, fits_val):
        x, g = xs[n][0], xs[n][1].grad
        Xc = chan_rows(x)
        std = Xc.std(1, unbiased=False)
        win = ((Xc - f["t"][:, None]).abs() < std[:, None]).double().mean().item()
        out.append(dict(g=g.norm().item(), gx=(g.norm() / x.norm()).item(), win=win))
    model.zero_grad(set_to_none=True)
    model.load_state_dict(state)
    model.eval()
    return out, loss.item()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--m", default="1234")
    ap.add_argument("--json", required=True)
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    c100.apply()
    dev = "cuda"
    t0 = time.time()
    log = lambda s: print(f"[{time.time() - t0:7.1f}s] {a.tag} {s}", flush=True)
    ck, model = qc18.verify.load(a.ckpt, dev)
    state = copy.deepcopy(model.state_dict())
    (xtr, ytr), (xv, yv) = qc18.verify.split(dev)
    nc = names_convs(model)
    res = dict(tag=a.tag, ckpt=a.ckpt, names=[n for n, _ in nc], val_acc=qc18.train.accuracy(model, xv, yv))
    log(f"val acc {res['val_acc']:.4f}")
    fits_val = []
    if "2" in a.m or "1" in a.m or "4" in a.m:
        res["shape"], res["m1"], res["m2"] = [], [], []
        for n, c in nc:
            X = capture(model, c, xv)
            res["shape"].append(list(X.shape[1:]))
            if "1" in a.m:
                res["m1"].append(m1(X))
            f = fit(X)
            fits_val.append(f)
            if "2" in a.m:
                res["m2"].append(m2(c, X, f))
            del X
            torch.cuda.empty_cache()
            log(f"M1/M2 {n} {res['m2'][-1] if res['m2'] else ''}")
    def save():
        with open(a.json, "w") as fh:
            json.dump(res, fh, indent=1)

    save()
    if "3" in a.m:
        res["m3"] = m3(model, state, nc, xtr[:10000], xv, yv, log)
        save()
    if "4" in a.m:
        res["m4"], res["m4_loss"] = m4(model, state, nc, xtr[:500], ytr[:500], fits_val)
        log(f"M4 loss {res['m4_loss']:.4f}")
    save()
    log("done")


if __name__ == "__main__":
    main()
