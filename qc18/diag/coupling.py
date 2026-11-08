"""D7: coupling of single-tile moves (why individually-improving moves explode jointly), and SGD's own flips.

    python3 -m qc18.diag.coupling a CKPT --name NAME --out-dir DIR
    python3 -m qc18.diag.coupling b CKPT --name NAME --out-dir DIR [--seeds 0,1,2] [--warm 50] [--ks 1,20]

Conventions of polish.py: fp32 (no TF32), eval mode, A = perm(4321)[:10000] of the 45k split (unaugmented), BN
recalibrated once on train[:10000] on the base network and then held fixed unless "recal" is stated (recal_v: the
network of the stored v; train.recal_bn would use hard(theta) and ignore moves written into v).  Exact losses
resume from the cached input of the earliest block containing a modified conv; L = mean CE over A, and per-chunk
means over 10 chunks of 1000 for se / z (z = mean dL / (std_chunks / sqrt 10)).
Part a: the top-16 moves exactly as polish.py round 1 ranks them (top-512 first-order candidates, exact dL, keep
  dL < 0 sorted ascending, first 16).  Per move: layer, block row/col, out/in channels (+ kernel tap), v, v', dL.
  All 120 pairwise interactions I_ij = L(i+j) - L(i) - L(j) + L0 grouped by relation (same layer & row / same
  layer other row / adjacent layers = direct dataflow producer->consumer conv / other).  Joint dL of the 16 without
  and with BN recal; same for one move per (layer, row) (the best).  Tensor level on A[:512]: per conv relative
  change ||dy||/||y|| of the pre-BN conv output and of the BN output (joint-16 vs base, base BN stats), the first
  layer (forward order) above 0.5, and the per-(layer,row) relative change of the moved row's own output channels.
Part b: rebuilds the training recipe from a snapshot checkpoint (SGD nesterov + AdamW on theta, LambdaLR position
  = (epoch+1) * steps/epoch, bf16 autocast, augmentation; eager instead of torch.compile).  Optimizer state is not
  in the checkpoint: --warm steps first (momentum / Adam moments), then base = (state, hard(theta)) and K steps;
  S = tiles whose hard(theta) changed.  Base eval net: the pre-step state with v = hard(theta) (BN recal on it).
  Per i in S (<= 400 random if larger): exact dL_i and z; sum; joint dL of S without / with BN recal.
"""
import argparse
import json
import math
import os

import numpy as np
import torch
import torch.nn.functional as F

from ..data import augment, prep, split
from ..model import QCResNet18
from ..qcconv import vset
from .common import layer_names, load
from .evidence import apply, flat_v, train_loss
from .local_model import block_index, cache_inputs, tail
from .polish import locate, predicted_best
from .snap import hard_v

NCH = 10


class Multi:
    """Exact loss on (x, y) with any set of tile moves, resumed from the earliest affected block's cached input."""

    def __init__(self, model, x, y):
        self.model, self.y, self.hs, self.bidx = model, y, cache_inputs(model, x), block_index(model)

    @torch.no_grad()
    def L(self, moves):
        """moves: [(conv, r, c, vnew)] -> per-chunk mean CE (float64 [NCH])."""
        old = [(cv, r, c, cv.v[r, c].clone()) for cv, r, c, _ in moves]
        for cv, r, c, w in moves:
            cv.v[r, c] = w
        try:
            j = min([self.bidx[m[0]] for m in moves], default=7)
            ce = F.cross_entropy(tail(self.model, j, self.hs[j + 1]).double(), self.y, reduction="none")
            return ce.reshape(NCH, -1).mean(1)
        finally:
            for cv, r, c, w in reversed(old):
                cv.v[r, c] = w


def zstat(d):
    """per-chunk dL [NCH] -> (mean, z)."""
    m, se = d.mean().item(), (d.std() / NCH ** 0.5).item()
    return m, m / se if se > 0 else float("nan")


def tile_info(model, names, off, t):
    cv, r, c = locate(model, off, t)
    li = model.qconvs().index(cv)
    cp = math.ceil(cv.cin / cv.b) * cv.b
    tap, ci = divmod(c * cv.b, cp)
    return dict(tile=int(t), layer=names[li], li=li, r=r, c=c, out_ch=[r * cv.b, (r + 1) * cv.b - 1],
                in_ch=[ci, ci + cv.b - 1], tap=list(divmod(tap, cv.k))), (cv, r, c)


def adjacency(names):
    """Direct dataflow producer -> consumer conv pairs (by name)."""
    adj = {("stem.conv", "blocks.0.c1.conv")}
    for j in range(8):
        adj.add((f"blocks.{j}.c1.conv", f"blocks.{j}.c2.conv"))
        if j < 7:
            nxt = [f"blocks.{j + 1}.c1.conv"] + ([f"blocks.{j + 1}.sc.conv"] if f"blocks.{j + 1}.sc.conv" in names else [])
            for src in [f"blocks.{j}.c2.conv"] + ([f"blocks.{j}.sc.conv"] if f"blocks.{j}.sc.conv" in names else []):
                adj.update((src, d) for d in nxt)
    return adj


def relation(a, b, adj):
    if a["layer"] == b["layer"]:
        return "same_row" if a["r"] == b["r"] else "same_layer"
    return "adjacent" if (a["layer"], b["layer"]) in adj or (b["layer"], a["layer"]) in adj else "other"


@torch.no_grad()
def activations(model, x):
    """{conv name: (pre-BN output, BN output)} on x, eval mode."""
    out, hooks = {}, []
    for n, cb in model.convbns():
        hooks.append(cb.conv.register_forward_hook(lambda m, i, o, n=n: out.__setitem__(n + ".conv", [o.clone()])))
        hooks.append(cb.bn.register_forward_hook(lambda m, i, o, n=n: out[n + ".conv"].append(o.clone())))
    model.eval()
    model(x)
    for h in hooks:
        h.remove()
    return out


@torch.no_grad()
def recal_v(model, x):
    """train.recal_bn with every QCConv2d kept in eval mode, i.e. BN statistics of the network of the stored v
    (train.recal_bn runs the convs in train mode = hard(theta), which ignores moves written into v)."""
    model.train()
    for c in model.qconvs():
        c.eval()
    bns = [m for m in model.modules() if isinstance(m, torch.nn.BatchNorm2d)]
    for m in bns:
        m.reset_running_stats()
        m.momentum = None
    for i in range(0, len(x), 500):
        model(prep(x[i:i + 500]))
    for m in bns:
        m.momentum = 0.1
    model.eval()


def joint(model, state0, off, tiles, vnew, xa_raw, ya, xr, L0):
    apply(model, off, tiles, vnew)
    r = dict(no_recal=train_loss(model, xa_raw, ya) - L0)
    recal_v(model, xr)
    r["recal"] = train_loss(model, xa_raw, ya) - L0
    model.load_state_dict(state0)
    return r


def part_a(a, data):
    xtr, ytr, A = data
    ck, model = load(a.ckpt)
    V = vset(ck["args"]["b"], ck["args"]["mode"] == "signed").cuda()
    names = [n + ".conv" for n in layer_names()]
    xa_raw, ya, xr = xtr[A], ytr[A], xtr[:10000]
    xa = prep(xa_raw)
    recal_v(model, xr)
    model.eval()
    state0 = {k: t.clone() for k, t in model.state_dict().items()}
    v, off = flat_v(model)
    mb, kb = predicted_best(model, xa, ya, V)
    pred, tiles = mb.sort()
    tiles = tiles[:a.cands]
    ev = Multi(model, xa, ya)
    L0c = ev.L([])
    moves = []
    for t in tiles.tolist():
        info, (cv, r, c) = tile_info(model, names, off, t)
        info.update(v=v[t].tolist(), v_new=V[kb[t]].tolist(), pred=mb[t].item())
        info["dL"] = (ev.L([(cv, r, c, V[kb[t]])]) - L0c).mean().item()
        moves.append((info, (cv, r, c, V[kb[t]])))
    moves = sorted([m for m in moves if m[0]["dL"] < 0], key=lambda m: m[0]["dL"])[:16]
    adj = adjacency(names)
    pairs = []
    for i in range(16):
        for j in range(i + 1, 16):
            Lij = (ev.L([moves[i][1], moves[j][1]]) - L0c).mean().item()
            pairs.append(dict(i=i, j=j, rel=relation(moves[i][0], moves[j][0], adj),
                              I=Lij - moves[i][0]["dL"] - moves[j][0]["dL"]))
    del ev
    torch.cuda.empty_cache()
    L0 = train_loss(model, xa_raw, ya)
    tt = torch.tensor([m[0]["tile"] for m in moves], device="cuda")
    vn = torch.stack([m[1][3] for m in moves])
    res = dict(ckpt=a.ckpt, L0=L0, moves=[m[0] for m in moves], pairs=pairs,
               sum_single=sum(m[0]["dL"] for m in moves), sum_I=sum(p["I"] for p in pairs))
    res["joint16"] = joint(model, state0, off, tt, vn, xa_raw, ya, xr, L0)
    seen, one = set(), []
    for k, m in enumerate(moves):
        if (m[0]["layer"], m[0]["r"]) not in seen:
            seen.add((m[0]["layer"], m[0]["r"]))
            one.append(k)
    res["one_per_row"] = dict(n=len(one), sum_single=sum(moves[k][0]["dL"] for k in one),
                              **joint(model, state0, off, tt[one], vn[one], xa_raw, ya, xr, L0))
    grp = {}
    for p in pairs:
        grp.setdefault(p["rel"], []).append(p["I"])
    res["I_by_relation"] = {k: dict(n=len(x), mean=float(np.mean(x)), median=float(np.median(x)),
                                    min=float(np.min(x)), max=float(np.max(x)), sum=float(np.sum(x)))
                            for k, x in grp.items()}
    I = np.array([p["I"] for p in pairs])
    res["I_all"] = dict(mean=float(I.mean()), median=float(np.median(I)), q10=float(np.quantile(I, .1)),
                        q90=float(np.quantile(I, .9)), max=float(I.max()), frac_pos=float((I > 0).mean()))
    # tensor level
    x5 = xa[:512]
    base = activations(model, x5)
    apply(model, off, tt, vn)
    new = activations(model, x5)
    model.load_state_dict(state0)
    rc = lambda y0, y1: ((y1 - y0).norm() / y0.norm()).item()
    res["act"] = {n: dict(pre=rc(base[n][0], new[n][0]), post=rc(base[n][1], new[n][1])) for n in names}
    res["first_pre_gt_0.5"] = next((n for n in names if res["act"][n]["pre"] > 0.5), None)
    res["first_post_gt_0.5"] = next((n for n in names if res["act"][n]["post"] > 0.5), None)
    rows = {}
    for m in res["moves"]:
        rows.setdefault((m["layer"], m["r"]), []).append(m["dL"])
    res["rows"] = []
    for (n, r), dls in rows.items():
        b = model.qconvs()[names.index(n)].b
        y0, y1 = base[n][0][:, r * b:(r + 1) * b], new[n][0][:, r * b:(r + 1) * b]
        z0, z1 = base[n][1][:, r * b:(r + 1) * b], new[n][1][:, r * b:(r + 1) * b]
        res["rows"].append(dict(layer=n, r=r, n_moves=len(dls), sum_dL=sum(dls), pre=rc(y0, y1), post=rc(z0, z1)))
    return res


def build_training(ck):
    """Model + optimizers + schedulers of train.py (QC, qopt adam) at the checkpoint's step position."""
    A = argparse.Namespace(**ck["args"])
    assert A.mode != "dense" and A.qopt == "adam" and A.homotopy == "none" and A.relax == "none"
    model = QCResNet18(A.mode, A.b, A.estimator, A.tau0).cuda().to(memory_format=torch.channels_last)
    model.load_state_dict(ck["state"])
    theta = [p for n, p in model.named_parameters() if n.endswith("theta")]
    decay = [model.fc.weight]
    other = [p for p in model.parameters() if all(p is not q for q in theta + decay)]
    opts = [torch.optim.SGD([dict(params=decay, weight_decay=A.wd), dict(params=other, weight_decay=0.0)],
                            lr=A.lr, momentum=0.9, nesterov=True),
            torch.optim.AdamW(theta, lr=A.qlr, weight_decay=A.qwd)]
    spe = 45000 // A.bs
    steps, warm = A.epochs * spe, int(min(A.warmup, A.epochs / 10) * spe)
    cos = lambda t: 0.5 * (1 + math.cos(math.pi * t / steps))
    sched = [torch.optim.lr_scheduler.LambdaLR(opts[0], lambda t: (t + 1) / warm if t < warm else cos(t)),
             torch.optim.lr_scheduler.LambdaLR(opts[1], cos)]
    t0 = (ck["epoch"] + 1) * spe
    for s in sched:
        for _ in range(t0):
            s.step()
    return A, model, opts, sched, t0


def train_steps(A, model, opts, sched, xtr, ytr, idx_iter, n):
    model.train()
    for _ in range(n):
        idx = next(idx_iter)
        x, y = prep(augment(xtr[idx])), ytr[idx]
        with torch.autocast("cuda", torch.bfloat16, enabled=bool(A.amp)):
            out = model(x)
        loss = F.cross_entropy(out.float(), y)
        for o in opts:
            o.zero_grad(set_to_none=True)
        loss.backward()
        for o, s in zip(opts, sched):
            o.step()
            s.step()


def part_b(a, data):
    xtr, ytr, A_ = data
    xa_raw, ya, xr = xtr[A_], ytr[A_], xtr[:10000]
    xa = prep(xa_raw)
    ck = torch.load(a.ckpt, map_location="cuda")
    names = [n + ".conv" for n in layer_names()]
    Ks = sorted(int(k) for k in a.ks.split(","))
    out = dict(ckpt=a.ckpt, epoch=ck["epoch"] + 1, warm=a.warm, runs=[])
    for seed in [int(s) for s in a.seeds.split(",")]:
        torch.manual_seed(1000 + seed)
        A, model, opts, sched, t0 = build_training(ck)
        perm = torch.randperm(len(xtr), device="cuda", generator=torch.Generator("cuda").manual_seed(seed))
        idx_iter = iter(perm[i * A.bs:(i + 1) * A.bs] for i in range(len(xtr) // A.bs))
        train_steps(A, model, opts, sched, xtr, ytr, idx_iter, a.warm)
        state0 = {k: t.clone() for k, t in model.state_dict().items()}
        v0 = [t.float().cuda() for t in hard_v(model)]
        vk, done = {}, 0
        for K in Ks:
            train_steps(A, model, opts, sched, xtr, ytr, idx_iter, K - done)
            done = K
            vk[K] = [t.float().cuda() for t in hard_v(model)]
        del model, opts, sched
        _, ev_model = load(a.ckpt)
        ev_model.load_state_dict(state0)
        for c, w in zip(ev_model.qconvs(), v0):
            c.v.copy_(w)
        recal_v(ev_model, xr)
        ev_model.eval()
        base = {k: t.clone() for k, t in ev_model.state_dict().items()}
        _, off = flat_v(ev_model)
        L0 = train_loss(ev_model, xa_raw, ya)
        ev = Multi(ev_model, xa, ya)
        L0c = ev.L([])
        for K in Ks:
            fb = torch.cat([w.reshape(-1, w.shape[-1]) for w in v0])
            fk = torch.cat([w.reshape(-1, w.shape[-1]) for w in vk[K]])
            S = torch.nonzero((fb != fk).any(1))[:, 0]
            sub = S[torch.randperm(len(S), generator=torch.Generator().manual_seed(seed))[:a.max_moves].cuda()]
            dls, zs, per_layer = [], [], {}
            for t in sub.tolist():
                info, (cv, r, c) = tile_info(ev_model, names, off, t)
                m, z = zstat(ev.L([(cv, r, c, fk[t])]) - L0c)
                dls.append(m)
                zs.append(z)
                per_layer.setdefault(info["layer"], []).append(m)
            dls, zs = np.array(dls), np.array(zs)
            del ev
            torch.cuda.empty_cache()
            r = dict(seed=seed, K=K, step0=t0 + a.warm, n_S=len(S), n_meas=len(sub),
                     frac_neg=float((dls < 0).mean()) if len(dls) else None,
                     median_z=float(np.median(zs)) if len(zs) else None,
                     frac_z_lt_m2=float((zs < -2).mean()) if len(zs) else None,
                     sum_dL=float(dls.sum()), sum_dL_scaled=float(dls.sum() * len(S) / max(1, len(sub))),
                     L0=L0, per_layer={k: dict(n=len(x), sum=float(np.sum(x))) for k, x in per_layer.items()},
                     **{"joint_" + k: x for k, x in
                        joint(ev_model, base, off, S, fk[S], xa_raw, ya, xr, L0).items()})
            ev = Multi(ev_model, xa, ya)
            out["runs"].append(r)
            print(a.name, json.dumps({k: x for k, x in r.items() if k != "per_layer"}), flush=True)
        del ev, ev_model
        torch.cuda.empty_cache()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("part", choices=["a", "b"])
    ap.add_argument("ckpt")
    ap.add_argument("--name", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--cands", type=int, default=512)
    ap.add_argument("--seeds", default="0,1,2")
    ap.add_argument("--warm", type=int, default=50)
    ap.add_argument("--ks", default="1,20")
    ap.add_argument("--max-moves", type=int, default=400)
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.benchmark = True
    os.makedirs(a.out_dir, exist_ok=True)
    (xtr, ytr), _ = split("cuda")
    A = torch.randperm(len(xtr), generator=torch.Generator().manual_seed(4321)).cuda()[:10000]
    res = (part_a if a.part == "a" else part_b)(a, (xtr, ytr, A))
    with open(os.path.join(a.out_dir, f"{a.part}_{a.name}.json"), "w") as f:
        json.dump(res, f, indent=1)
    if a.part == "a":
        print(a.name, json.dumps({k: res[k] for k in ("L0", "sum_single", "sum_I", "joint16", "one_per_row",
                                                       "I_all", "I_by_relation", "first_pre_gt_0.5",
                                                       "first_post_gt_0.5")}), flush=True)


if __name__ == "__main__":
    main()
