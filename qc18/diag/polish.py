"""D6: verified greedy local search over QC tiles (polishing with exact, measured single-tile moves).

    python3 -m qc18.diag.polish CKPT --name NAME --out-dir DIR [--control] [--minutes 75] [--save PATH]

model.eval() (fixed function given BN stats), fp32 (no TF32), unaugmented train data; the test set is never used.
Fixed disjoint subsets of the 45k train split (seeded permutation 4321): A = perm[:10000] (selection; = the D5 loss
subset of evidence.py), B = perm[10000:20000] (held-out train loss); the 5k val split for accuracy only.
Per round:
 1. recal_v (common.py: BN stats of the network of the stored v) on train[:10000] (as at checkpoint time /
    evidence.py).  g = dL_A/dv (mean CE over A) and, per tile, the best legal v' != v in V by first-order
    predicted dL = g . (v' - v).
 2. Candidates: the --cands tiles with the most negative predicted dL (--control: --cands uniformly random tiles,
    each with a uniformly random legal v' != v).  Exact single-move dL on A per candidate (forward resumed from the
    cached input of the block containing the conv; whole A in one batch).  Keep measured dL < 0, sorted ascending.
 3. Greedy: add kept moves in that order; after every --block additions (and after the last partial block) measure
    the joint loss on A (full forward, same BN stats); if it went up versus before this block, revert the block and
    stop this round.
 4. Log loss A before / after (round-start BN stats), then recal_v and log loss A, loss B, val accuracy.
Stop after --rounds rounds, after 2 consecutive rounds with 0 accepted, or when the next round (estimated by the
last round's duration) would exceed --minutes.  Saves the polished checkpoint (BN recalibrated, same format as
best.pt: args, state, epoch, val) and DIR/<name>.json.
"""
import argparse
import json
import os
import time

import torch

from ..data import prep, split
from ..qcconv import vset
from ..train import accuracy
from .common import load, recal_v
from .evidence import apply, flat_v, train_loss, v_index
from .local_model import Evaluator, grads


def predicted_best(model, xa, ya, V):
    """Per flat tile: (predicted dL of the best legal alternative, its index in V) from g on all of A."""
    v, _ = flat_v(model)
    g = grads(model, xa, ya)
    g = torch.cat([t.reshape(-1, t.shape[-1]) for t in g]).double()
    P = g @ V.double().T - (g * v.double()).sum(-1, keepdim=True)
    P.scatter_(1, v_index(v, V)[:, None], float("inf"))
    return P.min(1)


def locate(model, off, t):
    """flat tile -> (conv, r, c)."""
    convs = model.qconvs()
    i = int(torch.searchsorted(torch.as_tensor(off), torch.tensor(t), right=True)) - 1
    c = convs[i]
    r, cc = divmod(t - int(off[i]), c.v.shape[1])
    return c, r, cc


def run_round(model, a, V, xa, ya, xa_raw, xr, xb, yb, xva, yva, gen):
    t0 = time.time()
    recal_v(model, xr)
    model.eval()
    v, off = flat_v(model)
    N = len(v)
    if a.control:
        tiles = torch.randperm(N, generator=gen, device="cuda")[:a.cands]
        k = torch.randint(len(V) - 1, (len(tiles),), generator=gen, device="cuda")
        cur = v_index(v[tiles], V)
        k = k + (k >= cur).long()                                       # uniform over V \ {v}
        pred = torch.full((len(tiles),), float("nan"), dtype=torch.float64, device="cuda")
    else:
        mb, kb = predicted_best(model, xa, ya, V)
        pred, tiles = mb.sort()
        pred, tiles = pred[:a.cands], tiles[:a.cands]
        k = kb[tiles]
    ev = Evaluator(model, xa, ya)
    L0 = ev.L()
    meas = []
    for t, kk in zip(tiles.tolist(), k.tolist()):
        c, r, cc = locate(model, off, t)
        meas.append(ev.L(c, r, cc, V[kk]) - L0)
    del ev
    torch.cuda.empty_cache()
    meas = torch.tensor(meas, dtype=torch.float64)
    keep = torch.nonzero(meas < 0)[:, 0]
    keep = keep[meas[keep].argsort()]
    tk, vk = tiles[keep.cuda()], V[k[keep.cuda()]]
    # greedy joint acceptance in blocks
    acc, Lprev, joint = 0, L0, []
    for s in range(0, len(keep), a.block):
        tb = tk[s:s + a.block]
        old = v[tb].clone()
        apply(model, off, tb, vk[s:s + a.block])
        Lj = train_loss(model, xa_raw, ya)
        joint.append(Lj)
        if Lj > Lprev:
            apply(model, off, tb, old)
            break
        acc, Lprev = acc + len(tb), Lj
    L_after = Lprev
    recal_v(model, xr)
    r = dict(n_cand=len(tiles), n_kept=len(keep), n_accepted=acc, loss_A_before=L0, loss_A_after=L_after,
             joint_losses=joint, sum_measured_kept=meas[keep].sum().item(),
             sum_measured_accepted=meas[keep[:acc]].sum().item(),
             pred_cand_median=pred.median().item() if not a.control else None,
             meas_cand_median=meas.median().item(), frac_meas_neg=(meas < 0).double().mean().item(),
             loss_A_recal=train_loss(model, xa_raw, ya), loss_B=train_loss(model, xb, yb),
             val=accuracy(model, xva, yva), sec=time.time() - t0)
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--name", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--save", default="", help="path of the polished checkpoint (default: none)")
    ap.add_argument("--control", action="store_true")
    ap.add_argument("--cands", type=int, default=512)
    ap.add_argument("--block", type=int, default=16)
    ap.add_argument("--rounds", type=int, default=30)
    ap.add_argument("--minutes", type=float, default=75)
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.benchmark = True
    os.makedirs(a.out_dir, exist_ok=True)
    T0 = time.time()
    ck, model = load(a.ckpt)
    V = vset(ck["args"]["b"], ck["args"]["mode"] == "signed").cuda()
    (xtr, ytr), (xva, yva) = split("cuda")
    perm = torch.randperm(len(xtr), generator=torch.Generator().manual_seed(4321)).cuda()
    A, B = perm[:10000], perm[10000:20000]
    xa_raw, ya, xb, yb = xtr[A], ytr[A], xtr[B], ytr[B]
    xa, xr = prep(xa_raw), xtr[:10000]
    gen = torch.Generator(device="cuda").manual_seed(a.seed)
    res = dict(ckpt=a.ckpt, name=a.name, control=a.control, epoch=ck["epoch"] + 1, val_ckpt=ck["val"], args=vars(a))
    recal_v(model, xr)
    res["round0"] = dict(loss_A=train_loss(model, xa_raw, ya), loss_B=train_loss(model, xb, yb),
                         val=accuracy(model, xva, yva))
    print(a.name, "round 0", json.dumps(res["round0"]), flush=True)
    res["rounds"], zeros, last, stop = [], 0, 0.0, "rounds"
    out = os.path.join(a.out_dir, a.name + ".json")
    for it in range(1, a.rounds + 1):
        if (time.time() - T0) + last > 60 * a.minutes:
            stop = "time"
            break
        r = run_round(model, a, V, xa, ya, xa_raw, xr, xb, yb, xva, yva, gen)
        r["round"], r["elapsed"] = it, time.time() - T0
        last = r["sec"]
        res["rounds"].append(r)
        print(a.name, f"round {it}: cand {r['n_cand']} kept {r['n_kept']} acc {r['n_accepted']} "
              f"A {r['loss_A_before']:.5f}->{r['loss_A_after']:.5f} (recal {r['loss_A_recal']:.5f}) "
              f"B {r['loss_B']:.5f} val {r['val']:.4f}  {r['sec']:.0f}s", flush=True)
        with open(out, "w") as f:
            json.dump(res, f, indent=1)
        zeros = zeros + 1 if r["n_accepted"] == 0 else 0
        if zeros >= 2:
            stop = "2x0"
            break
    res["stop"], res["minutes"] = stop, (time.time() - T0) / 60
    # model is BN-recalibrated (end of the last round / round 0)
    final_val = accuracy(model, xva, yva)
    res["final_val"] = final_val
    with open(out, "w") as f:
        json.dump(res, f, indent=1)
    if a.save:
        torch.save(dict(args=ck["args"], state=model.state_dict(), epoch=ck["epoch"], val=final_val), a.save)
    print(a.name, "stop", stop, f"{res['minutes']:.1f} min, final val {final_val:.4f}", flush=True)


if __name__ == "__main__":
    main()
