"""D4/D5: per-tile first-order evidence for single-tile moves under large-batch gradients, and a polishing test.

    python3 -m qc18.diag.evidence CKPT [CKPT ...] --out-dir DIR

model.eval(), fp32 (no TF32), BN running stats as stored (verify.py: no recalibration), unaugmented train data.
D4: the 45k train split -> 10 disjoint contiguous chunks of 4500.  Per chunk c: g_c = dL_c/dv for every tile (L_c =
  mean CE over the chunk; autograd through expand = sum of the dense weight gradient along each cyclic diagonal, at
  the hard weights).  For every tile and every legal v' != v in V: P_c(v') = g_c . (v' - v); over chunks mean m(v'),
  se(v') = std_c (ddof 1) / sqrt(nchunks).  best = argmin_{v' != v} m;  z = m_best / se_best.
  Move type of the best move: nnz (|v'|_0 != |v|_0), sign (same support, signs differ), swap (same |.|_0, other support).
D5: rank the z < -3 tiles by m_best (most negative first); for q in {1, 5, 20} % of ALL tiles (capped at the number
  of z < -3 tiles) apply the best moves of the top-q tiles at once, recalibrate BN (train.recal_bn on train[:10000],
  as at checkpoint time; verify.py itself evaluates the stored stats), measure train loss (eval mode, fixed 10k train
  subset: seeded permutation 4321 of the 45k) and val accuracy.  Control: the same count of uniformly random tiles,
  each moved to a uniformly random legal v' != v (3 seeds).  Iterative: 3 rounds of [D4 with 5 chunks of 9000 on the
  current net, apply the best moves of the top 5 % (of all tiles) z < -3 tiles, recal BN, measure].
Writes DIR/<run>.json per checkpoint.
"""
import argparse
import json
import os

import numpy as np
import torch
import torch.nn.functional as F

from ..data import prep, split
from ..qcconv import vset
from ..train import accuracy, recal_bn
from .common import layer_names, load
from .local_model import grads

QS = (0.01, 0.05, 0.20)


def flat_v(model):
    """[N, b] all tiles (layer order of model.qconvs()), and layer offsets."""
    vs = [c.v.reshape(-1, c.b) for c in model.qconvs()]
    off = np.cumsum([0] + [len(v) for v in vs])
    return torch.cat(vs), off


def v_index(v, V, chunk=1 << 16):
    """index k with V[k] == v for every row of v [N, b]."""
    out = torch.empty(len(v), dtype=torch.long, device=v.device)
    for i in range(0, len(v), chunk):
        eq = (v[i:i + chunk, None, :] == V[None]).all(-1)
        assert (eq.sum(1) == 1).all()
        out[i:i + chunk] = eq.float().argmax(1)
    return out


def move_type(v, w):
    nv, nw = (v != 0).sum(-1), (w != 0).sum(-1)
    same_supp = ((v != 0) == (w != 0)).all(-1)
    return torch.where(nv != nw, 0, torch.where(same_supp, 1, 2))      # 0 nnz, 1 sign, 2 swap


TYPES = ("nnz", "sign", "swap")


def evidence(model, x, y, nchunks, V):
    """D4 on (x, y) split into nchunks contiguous chunks.  Returns dict of per-tile tensors (flat over layers)."""
    model.eval()
    n = len(x) // nchunks
    v, off = flat_v(model)
    s1 = torch.zeros(len(v), len(V), dtype=torch.float64, device=v.device)
    s2 = torch.zeros_like(s1)
    for c in range(nchunks):
        g = grads(model, prep(x[c * n:(c + 1) * n]), y[c * n:(c + 1) * n])
        g = torch.cat([t.reshape(-1, t.shape[-1]) for t in g]).double()
        P = g @ V.double().T - (g * v.double()).sum(-1, keepdim=True)   # [N, K] = g . (v' - v)
        s1 += P
        s2 += P * P
    m = s1 / nchunks
    var = ((s2 - nchunks * m * m) / (nchunks - 1)).clamp(min=0)
    se = var.sqrt() / nchunks ** 0.5
    cur = v_index(v, V)
    m.scatter_(1, cur[:, None], float("inf"))
    mb, kb = m.min(1)
    seb = se.gather(1, kb[:, None])[:, 0]
    z = mb / seb                                                          # se 0 -> +-inf / nan (none expected)
    return dict(v=v, off=off, cur=cur, m_best=mb, se_best=seb, z=z, k_best=kb,
                type=move_type(v, V[kb]), n_se0=int((seb == 0).sum()))


def summary(e, names):
    z, mb, t = e["z"], e["m_best"], e["type"]
    sig = z < -3
    N = len(z)
    per_layer = {}
    for i, nm in enumerate(names):
        a, b = e["off"][i], e["off"][i + 1]
        per_layer[nm] = dict(n=int(b - a), frac_z_lt_m3=sig[a:b].double().mean().item(),
                             frac_z_lt_m2=(z[a:b] < -2).double().mean().item(),
                             frac_m_lt_0=(mb[a:b] < 0).double().mean().item())
    mix = lambda msk: {T: int(((t == k) & msk).sum()) for k, T in enumerate(TYPES)}
    return dict(n_tiles=N, n_se0=e["n_se0"], frac_m_lt_0=(mb < 0).double().mean().item(),
                frac_z_lt_m2=(z < -2).double().mean().item(), frac_z_lt_m3=sig.double().mean().item(),
                n_z_lt_m3=int(sig.sum()), sum_m_best_z_lt_m3=mb[sig].sum().item(),
                median_m_best_z_lt_m3=mb[sig].median().item() if sig.any() else float("nan"),
                median_m_best_all=mb.median().item(), median_z_all=z.median().item(),
                mix_z_lt_m3=mix(sig), mix_all=mix(torch.ones_like(sig)), per_layer=per_layer)


def apply(model, off, tiles, vnew):
    """Set flat tiles (LongTensor) to vnew [n, b]."""
    convs = model.qconvs()
    off_t = torch.as_tensor(off, device=tiles.device)
    li = torch.searchsorted(off_t, tiles, right=True) - 1
    for i, c in enumerate(convs):
        sel = li == i
        if sel.any():
            c.v.view(-1, c.b)[tiles[sel] - off[i]] = vnew[sel].to(c.v.dtype)


@torch.no_grad()
def train_loss(model, x, y, bs=1000):
    model.eval()
    s = sum(F.cross_entropy(model(prep(x[i:i + bs])).double(), y[i:i + bs], reduction="sum").item()
            for i in range(0, len(x), bs))
    return s / len(x)


def measure(model, xr, xl, yl, xva, yva, recal=True):
    if recal:
        recal_bn(model, xr)
    return dict(train_loss=train_loss(model, xl, yl), val=accuracy(model, xva, yva))


def run(path, a):
    ck, model = load(path)
    signed, b = ck["args"]["mode"] == "signed", ck["args"]["b"]
    V = vset(b, signed).cuda()
    names = layer_names()
    (xtr, ytr), (xva, yva) = split("cuda")
    perm = torch.randperm(len(xtr), generator=torch.Generator().manual_seed(4321)).cuda()[:10000]
    xl, yl = xtr[perm], ytr[perm]
    xr = xtr[:10000]
    v0 = [c.v.clone() for c in model.qconvs()]
    state0 = {k: t.clone() for k, t in model.state_dict().items()}

    def reset():
        model.load_state_dict(state0)

    res = dict(ckpt=path, epoch=ck["epoch"] + 1, b=b, signed=signed, K=len(V), val_ckpt=ck["val"])
    res["baseline_stored_bn"] = measure(model, xr, xl, yl, xva, yva, recal=False)
    res["baseline_recal"] = measure(model, xr, xl, yl, xva, yva)
    reset()
    e = evidence(model, xtr, ytr, a.chunks, V)
    res["d4"] = summary(e, names)
    print(path, json.dumps({k: v for k, v in res["d4"].items() if k != "per_layer"}), flush=True)
    # D5 one-shot polishing
    sig = torch.nonzero(e["z"] < -3)[:, 0]
    order = sig[e["m_best"][sig].argsort()]
    N = len(e["z"])
    res["d5"] = []
    gen = torch.Generator(device="cuda").manual_seed(0)
    for q in QS:
        n = min(round(q * N), len(order))
        top = order[:n]
        apply(model, e["off"], top, V[e["k_best"][top]])
        r = dict(q=q, n=n, pred_sum_m=e["m_best"][top].sum().item(),
                 polish_stored_bn=measure(model, xr, xl, yl, xva, yva, recal=False))
        r["polish"] = measure(model, xr, xl, yl, xva, yva)
        reset()
        ctl = []
        for s in range(a.ctl_seeds):
            tiles = torch.randperm(N, generator=gen, device="cuda")[:n]
            k = torch.randint(len(V) - 1, (n,), generator=gen, device="cuda")
            k = k + (k >= e["cur"][tiles]).long()                     # uniform over V \ {v}
            apply(model, e["off"], tiles, V[k])
            ctl.append(measure(model, xr, xl, yl, xva, yva))
            reset()
        r["control"] = ctl
        res["d5"].append(r)
        print(f"  q {q}: n {n} polish {r['polish']} control {ctl}", flush=True)
    # iterative rounds
    res["iter"] = []
    for it in range(a.rounds):
        e2 = evidence(model, xtr, ytr, a.iter_chunks, V)
        s2 = summary(e2, names)
        sig = torch.nonzero(e2["z"] < -3)[:, 0]
        order = sig[e2["m_best"][sig].argsort()]
        n = min(round(0.05 * N), len(order))
        top = order[:n]
        apply(model, e2["off"], top, V[e2["k_best"][top]])
        r = dict(round=it + 1, n=n, pred_sum_m=e2["m_best"][top].sum().item(),
                 d4={k: v for k, v in s2.items() if k != "per_layer"}, **measure(model, xr, xl, yl, xva, yva))
        res["iter"].append(r)
        print(f"  round {it + 1}: n {n} loss {r['train_loss']:.5f} val {r['val']:.4f} "
              f"frac z<-3 {s2['frac_z_lt_m3']:.4f}", flush=True)
    reset()
    assert all(torch.equal(c.v, w) for c, w in zip(model.qconvs(), v0))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="+")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--chunks", type=int, default=10)
    ap.add_argument("--iter-chunks", type=int, default=5)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--ctl-seeds", type=int, default=3)
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.benchmark = True
    os.makedirs(a.out_dir, exist_ok=True)
    for p in a.ckpts:
        r = run(p, a)
        with open(os.path.join(a.out_dir, os.path.basename(os.path.dirname(p)) + ".json"), "w") as f:
            json.dump(r, f, indent=1)


if __name__ == "__main__":
    main()
