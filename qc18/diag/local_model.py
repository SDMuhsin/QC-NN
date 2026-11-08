"""M2: local loss model around a checkpoint (single-tile moves in shift space).

    python3 -m qc18.diag.local_model CKPT [CKPT ...] --out JSON

model.eval() (BN running stats -> fixed function), fp32, fixed 2000 unaugmented train images (set A; set B = the
next 2000 of the same seeded permutation, disjoint, for the noise check).  L = mean CE.  g = dL/dv for every tile
(v the coefficient vector; autograd through expand = the sum of the dense weight gradient along each cyclic
diagonal).  ~50 random tiles per conv; per tile the moves Delta = v' - v:
  runner: v' = argmax over V \\ {v} of score = <z, v'> - |v'|_0 / 2,  z = theta / alpha_r
  rand1, rand2: two distinct random legal v' differing from v in exactly one shift slot
dL(eps) = L(v + eps Delta) - L0 (only that tile changed, BN/scales unchanged) for eps in 0.25, 0.5, 1;
P1 = g . Delta;  quadratic f(eps) = B eps + C eps^2 through (0,0), (.25, dL(.25)), (.5, dL(.5)): Pq = B + C.
Forwards resume from the input of the block containing the conv (cached), batch = the 2000 images.
"""
import argparse
import json
import math

import numpy as np
import torch
import torch.nn.functional as F
from scipy.stats import pearsonr, spearmanr

from ..data import prep, split
from ..qcconv import row_alpha, vset
from .common import load

EPS = (0.25, 0.5, 1.0)


def block_index(model):
    """conv module -> block index (-1: stem)."""
    idx = {model.stem.conv: -1}
    for j, blk in enumerate(model.blocks):
        for cb in (blk.c1, blk.c2, blk.sc):
            if cb is not None:
                idx[cb.conv] = j
    return idx


def tail(model, j, h):
    if j < 0:
        h, j = F.relu(model.stem(h)), 0
    for blk in model.blocks[j:]:
        h = blk(h)
    return model.fc(h.mean((2, 3)))


@torch.no_grad()
def cache_inputs(model, x):
    """[input of stem (=x), input of block 0, ..., input of block 7]."""
    hs = [x]
    h = F.relu(model.stem(x))
    for blk in model.blocks:
        hs.append(h)
        h = blk(h)
    return hs


def loss_of(logits, y):
    return F.cross_entropy(logits.double(), y, reduction="mean").item()


class Evaluator:
    def __init__(self, model, x, y, bf16=False):
        self.model, self.y, self.bf16 = model, y, bf16
        with torch.autocast("cuda", torch.bfloat16, enabled=bf16):
            self.hs = cache_inputs(model, x)
        self.bidx = block_index(model)

    @torch.no_grad()
    def L(self, conv=None, r=0, c=0, vnew=None):
        """Loss with tile (r, c) of conv set to vnew (restored afterwards); None -> unmodified network."""
        j = self.bidx[conv] if conv is not None else -1
        if conv is not None:
            old = conv.v[r, c].clone()
            conv.v[r, c] = vnew
        try:
            with torch.autocast("cuda", torch.bfloat16, enabled=self.bf16):
                out = tail(self.model, j, self.hs[j + 1])
            return loss_of(out.float(), self.y)
        finally:
            if conv is not None:
                conv.v[r, c] = old


def grads(model, x, y, bs=500):
    convs = model.qconvs()
    for c in convs:
        c.v.requires_grad_(True)
        c.v.grad = None
    for i in range(0, len(x), bs):
        loss = F.cross_entropy(model(x[i:i + bs]), y[i:i + bs], reduction="sum") / len(x)
        loss.backward()
    g = [c.v.grad.detach().clone() for c in convs]
    for c in convs:
        c.v.requires_grad_(False)
        c.v.grad = None
    return g


def one_slot_moves(v):
    """All legal v' (signed, <= 2 nonzeros) differing from v in exactly one shift slot."""
    out, nnz = [], int((v != 0).sum())
    for s in range(len(v)):
        for val in (-1.0, 0.0, 1.0):
            if val == v[s]:
                continue
            if v[s] == 0 and nnz >= 2:                         # would add a third nonzero
                continue
            w = v.clone()
            w[s] = val
            out.append(w)
    return out


def sample_moves(model, per_conv, gen):
    V = vset(model.qconvs()[0].b, True).cuda()
    nnzV = (V != 0).sum(1).float()
    moves = []
    for li, c in enumerate(model.qconvs()):
        R, Cb, b = c.v.shape
        z = c.theta.detach() / row_alpha(c.theta)
        tiles = torch.randperm(R * Cb, generator=gen)[:per_conv]
        for t in tiles.tolist():
            r, cc = divmod(t, Cb)
            v = c.v[r, cc].clone()
            sc = z[r, cc] @ V.T - nnzV / 2
            cur = (V == v).all(1)
            assert cur.sum() == 1
            sc[cur] = -math.inf
            moves.append(dict(layer=li, r=r, c=cc, type="runner", vnew=V[sc.argmax()].clone(),
                              score_gap=(z[r, cc] @ v - (v != 0).sum() / 2 - sc.max()).item()))
            cand = one_slot_moves(v)
            for k, i in enumerate(torch.randperm(len(cand), generator=gen)[:2].tolist()):
                moves.append(dict(layer=li, r=r, c=cc, type=f"rand{k + 1}", vnew=cand[i]))
    return moves


def stats(ms):
    d1 = np.array([m["dL"][2] for m in ms])
    p1 = np.array([m["P1"] for m in ms])
    pq = np.array([m["Pq"] for m in ms])
    ratio = np.array([abs(m["Cq"]) / max(abs(m["Bq"]), 1e-30) for m in ms])
    return dict(n=len(ms), pearson_P1=pearsonr(p1, d1)[0], spearman_P1=spearmanr(p1, d1)[0],
                pearson_Pq=pearsonr(pq, d1)[0], spearman_Pq=spearmanr(pq, d1)[0],
                sign_agree_P1=float(np.mean(np.sign(p1) == np.sign(d1))),
                frac_P1neg_dLpos=float(np.mean((p1 < 0) & (d1 > 0))),
                median_curv_over_lin=float(np.median(ratio)), median_abs_dL1=float(np.median(np.abs(d1))),
                median_abs_P1=float(np.median(np.abs(p1))))


def run(path, a):
    torch.manual_seed(0)
    ck, model = load(path)
    (xtr, ytr), _ = split("cuda")
    perm = torch.randperm(len(xtr), generator=torch.Generator().manual_seed(1234)).cuda()
    A, B = perm[:a.n], perm[a.n:2 * a.n]
    xa, ya, xb, yb = prep(xtr[A]), ytr[A], prep(xtr[B]), ytr[B]
    g = grads(model, xa, ya)
    ev = Evaluator(model, xa, ya)
    L0 = ev.L()
    with torch.no_grad():
        L0full = loss_of(torch.cat([model(xa[i:i + 500]) for i in range(0, a.n, 500)]), ya)
    # path check: resuming from every block input with an unchanged tile reproduces L0
    path_dev = max(abs(ev.L(c, 0, 0, c.v[0, 0].clone()) - L0) for c in model.qconvs())
    moves = sample_moves(model, a.per_conv, torch.Generator().manual_seed(0))
    convs = model.qconvs()
    for m in moves:
        c = convs[m["layer"]]
        v = c.v[m["r"], m["c"]]
        D = m["vnew"] - v
        m["P1"] = (g[m["layer"]][m["r"], m["c"]] @ D).item()
        m["dL"] = [ev.L(c, m["r"], m["c"], v + e * D) - L0 for e in EPS]
        a1, a2 = m["dL"][0], m["dL"][1]
        m["Cq"] = 8 * (a2 - 2 * a1)
        m["Bq"] = 8 * a1 - 2 * a2
        m["Pq"] = m["Bq"] + m["Cq"]
        m["v"], m["vnew"] = v.tolist(), m["vnew"].tolist()
    res = dict(ckpt=path, epoch=ck["epoch"] + 1, L0=L0, L0_full_forward=L0full, path_max_dev=path_dev, n_images=a.n,
               per_type={t: stats([m for m in moves if m["type"] == t]) for t in ("runner", "rand1", "rand2")})
    res["per_type"]["rand"] = stats([m for m in moves if m["type"] != "runner"])
    res["per_type"]["all"] = stats(moves)
    # noise check: 50 moves (every k-th) re-measured on the disjoint set B at eps = 1
    evb = Evaluator(model, xb, yb)
    L0b = evb.L()
    sub = moves[::max(1, len(moves) // a.noise)][:a.noise]
    db = []
    for m in sub:
        c = convs[m["layer"]]
        db.append(evb.L(c, m["r"], m["c"], torch.tensor(m["vnew"], device="cuda")) - L0b)
    da = [m["dL"][2] for m in sub]
    res["noise"] = dict(n=len(sub), pearson_A_vs_B=pearsonr(da, db)[0], spearman_A_vs_B=spearmanr(da, db)[0],
                        dL_A=da, dL_B=db)
    # bf16 check: 20 moves at eps = 1, bf16 forward vs fp32
    evh = Evaluator(model, xa, ya, bf16=True)
    L0h = evh.L()
    sub = moves[::max(1, len(moves) // 20)][:20]
    dh = [evh.L(convs[m["layer"]], m["r"], m["c"], torch.tensor(m["vnew"], device="cuda")) - L0h for m in sub]
    df = [m["dL"][2] for m in sub]
    res["bf16_check"] = dict(n=20, pearson=pearsonr(df, dh)[0], max_abs_diff=float(np.max(np.abs(np.subtract(df, dh)))),
                             median_abs_dL_fp32=float(np.median(np.abs(df))), dL_fp32=df, dL_bf16=dh)
    res["moves"] = moves
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--n", type=int, default=2000)
    ap.add_argument("--per-conv", type=int, default=50)
    ap.add_argument("--noise", type=int, default=50)
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.benchmark = True
    out = []
    for p in a.ckpts:
        r = run(p, a)
        out.append(r)
        print(f"{p}: epoch {r['epoch']} L0 {r['L0']:.5f} (full fwd {r['L0_full_forward']:.5f})  noise r "
              f"{r['noise']['pearson_A_vs_B']:.3f}  bf16 r {r['bf16_check']['pearson']:.3f}", flush=True)
        for t, s in r["per_type"].items():
            print(f"  {t:7s} " + " ".join(f"{k} {v:.4g}" for k, v in s.items()), flush=True)
        with open(a.out, "w") as f:
            json.dump(out, f)


if __name__ == "__main__":
    main()
