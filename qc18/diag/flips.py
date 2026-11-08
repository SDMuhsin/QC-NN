"""M1: flip dynamics of the hard coefficients from --snap snapshots (qc18/diag/snap.py).

    python3 -m qc18.diag.flips RUN_DIR [--out JSON]

change = a tile (block) whose coefficient vector differs from the previous snapshot.  Series: epoch-level
(v_ep000 .. v_epNNN) and each 20-step series (steps_epEEE.pt).  Per series: changed-tile fraction per transition;
reversal rate within k later snapshots (tile equals its pre-change config again in any of the next k snapshots;
only changes with >= k later snapshots counted); type mix (sign: same support, a kept sign flipped; swap: same
nonzero count, support differs; nnz: nonzero count changes); mean number of distinct configs visited by tiles that
changed at least once in the series.
"""
import argparse
import glob
import json
import os

import torch

from .common import layer_names

KS = (1, 3, 5)


def codes(vs):
    """list over convs of int8 [R, Cb, b] -> (int64 [T] code per tile (base 3), int64 [T] layer id)."""
    out, lid = [], []
    for i, v in enumerate(vs):
        t = (v.reshape(-1, v.shape[-1]).long() + 1)
        w = 3 ** torch.arange(t.shape[1])
        out.append((t * w).sum(1))
        lid.append(torch.full((t.shape[0],), i))
    return torch.cat(out), torch.cat(lid)


def analyse(series, lid, nl):
    """series: list of (code [T], raw [T, b]) snapshots."""
    C = torch.stack([c for c, _ in series])                   # [S, T]
    V = torch.stack([v for _, v in series])                    # [S, T, b]
    S = C.shape[0]
    ch = C[1:] != C[:-1]                                       # [S-1, T], change at transition t -> t+1
    res = dict(n_snap=S, changed_frac=ch.double().mean(1).tolist())
    rev, rev_l = {}, {}
    for k in KS:
        num = torch.zeros(nl)
        den = torch.zeros(nl)
        for t in range(S - 1 - k):                             # change t -> t+1, look at t+2 .. t+1+k
            m = ch[t]
            back = (C[t + 2:t + 2 + k] == C[t][None]).any(0) & m
            den += torch.bincount(lid[m], minlength=nl)
            num += torch.bincount(lid[back], minlength=nl)
        rev[k] = (num.sum() / den.sum()).item() if den.sum() else float("nan")
        rev_l[k] = (num / den.clamp(min=1)).tolist()
        res[f"n_changes_k{k}"] = int(den.sum())
    res["reversal"] = rev
    res["reversal_per_layer"] = rev_l
    a, b = V[:-1][ch], V[1:][ch]                               # [N, b] old / new
    na, nb = (a != 0).sum(1), (b != 0).sum(1)
    same_sup = ((a != 0) == (b != 0)).all(1)
    n = max(1, len(a))
    res["types"] = dict(sign=(same_sup & (na == nb)).sum().item() / n,
                        swap=(~same_sup & (na == nb)).sum().item() / n, nnz=(na != nb).sum().item() / n,
                        n=len(a))
    anych = ch.any(0)
    srt = C[:, anych].sort(0).values
    distinct = 1 + (srt[1:] != srt[:-1]).sum(0)
    res["distinct_configs_per_changed_tile"] = distinct.double().mean().item() if anych.any() else float("nan")
    res["n_changed_tiles"] = int(anych.sum())
    res["n_tiles"] = C.shape[1]
    return res


def load_series(vlists):
    out = []
    lid = None
    for vs in vlists:
        c, lid = codes(vs)
        out.append((c, torch.cat([v.reshape(-1, v.shape[-1]) for v in vs])))
    return out, lid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    d = os.path.join(a.run, "snap")
    names = layer_names()
    nl = len(names)
    eps = sorted(glob.glob(os.path.join(d, "v_ep*.pt")))
    ser, lid = load_series([torch.load(p) for p in eps])
    res = dict(layers=names, epoch=analyse(ser, lid, nl))
    for p in sorted(glob.glob(os.path.join(d, "steps_ep*.pt"))):
        s = torch.load(p)
        ser, lid = load_series(s["v"])
        r = analyse(ser, lid, nl)
        r["steps"] = s["steps"]
        res["steps_" + os.path.basename(p)[8:11]] = r
    out = a.out or os.path.join(os.path.dirname(a.run.rstrip("/")), "m1_flips.json")
    with open(out, "w") as f:
        json.dump(res, f, indent=1)
    for key, r in res.items():
        if key == "layers":
            continue
        cf = r["changed_frac"]
        print(f"{key}: changed/transition mean {sum(cf) / len(cf):.4f}  reversal "
              + " ".join(f"k{k} {r['reversal'][k]:.3f}" for k in KS)
              + f"  types {r['types']}  distinct {r['distinct_configs_per_changed_tile']:.2f}")
    print("->", out)


if __name__ == "__main__":
    main()
