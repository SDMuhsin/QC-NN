"""STE fidelity, part 2 (measurement only; binary model only; reuses build / groups / stats of fidelity.py).

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.diag.fidelity2 --ckpt BIN/last.pt --out JSON [--bsC 4096]

Groups: BN of c1 / c2 and BinAct t of b1 / b2 for blocks 0, 2, 4, 6 (16 groups).  N random Gaussian directions per
group (generator seed 1, drawn once per group and reused for every batch / eps / STE setting), ||d|| = 1,
delta = eps ||p_G|| d, pred = eps ||p_G|| <g_G, d>, actual = (L(p+delta) - L(p-delta)) / 2 (train-mode BN over the
whole batch, fp32, TF32 off, eager, mean CE, no aug).  Batches from the 45k train split:
  A = randperm(45000, seed 0)[:512] (= fidelity.py batch),  B = first 512 of randperm(seed 1) not in A,
  C = randperm(seed 2)[:bsC] (single forward / backward over the full batch, so BN stats are over all of C).
STE sweep (batch C, forward unchanged): g recomputed with every BinAct's backward set to
  clip  db/du = 1[|u| < w],            w in WC
  tri   db/du = (1 - |u|/w)+,          w in WT          (custom autograd Function _Sweep; scale irrelevant for corr)
and correlated with actual_C.  Also per BinAct on C: fraction of elements with |u| < w.
"""
import argparse
import json
import time

import torch
import torch.nn.functional as F

import qc18.train
from qc18b import binact, c100, data
from qc18b.diag.fidelity import build, groups, stats

class _Sweep(torch.autograd.Function):
    """b = 1[u > 0]; db/du = 1[|u| < w] (clip) or (1 - |u|/w)+ (tri).  Saves only u (memory-light)."""

    @staticmethod
    def forward(ctx, u, kind, w, k):
        ctx.save_for_backward(u)
        ctx.kind, ctx.w, ctx.k = kind, w, k
        return (u > 0).to(u.dtype)

    @staticmethod
    def backward(ctx, g):
        (u,) = ctx.saved_tensors
        ua = u.abs()
        d = (ua < ctx.w).to(g.dtype) if ctx.kind == "clip" else (1 - ua / ctx.w).clamp_min(0)
        return g * (ctx.k * d), None, None, None


def sweep_forward(self, x):
    return _Sweep.apply(x - self.t.view(1, -1, 1, 1), self._sweep[0], self._sweep[1], self._sweep[2])


EPS = (1e-2, 3e-2, 1e-1)
WC = (0.05, 0.1, 0.25, 0.5, 1.0, 2.0)
WT = (0.25, 0.5, 1.0)
SEL = {f"b{i}.{s}" for i in (0, 2, 4, 6) for s in ("c1.bn", "c2.bn", "b1.t", "b2.t")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", required=True)
    ap.add_argument("--n", type=int, default=32)
    ap.add_argument("--bsC", type=int, default=4096)
    ap.add_argument("--out", required=True)
    ap.add_argument("--k", type=float, default=1.0, help="sweep derivative scale K (per BinAct, so NOT a global scale)")
    ap.add_argument("--sweep-only", default="", help="JSON of a full run: recompute only the sweep projections (same "
                    "directions / batches), store them as proj['C_clip<w>_K<k>'] etc. in --out")
    a = ap.parse_args()
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False
    dev = "cuda"
    c100.apply()
    (xtr, ytr), _ = data.split(dev)
    n = len(xtr)
    pA = torch.randperm(n, generator=torch.Generator().manual_seed(0))
    iA = pA[:512]
    pB = torch.randperm(n, generator=torch.Generator().manual_seed(1))
    inA = torch.zeros(n, dtype=torch.bool)
    inA[iA] = True
    iB = pB[~inA[pB]][:512]
    iC = torch.randperm(n, generator=torch.Generator().manual_seed(2))[:a.bsC]
    assert not (set(iA.tolist()) & set(iB.tolist()))
    batches = {k: (qc18.train.prep(xtr[i.to(dev)]), ytr[i.to(dev)]) for k, i in (("A", iA), ("B", iB), ("C", iC))}
    m, args, o = build(a.ckpt, dev)
    G = [(nm, k, ps) for nm, k, ps in groups(m) if nm in SEL]
    bas = [(nm, mod) for nm, mod in m.named_modules() if isinstance(mod, binact.BinAct)]
    orig = {nm: (mod.ste, mod.w, mod.k) for nm, mod in bas}
    gen = torch.Generator(device=dev).manual_seed(1)
    with torch.no_grad():
        D = {nm: [[torch.randn(q.shape, device=dev, generator=gen) for q in ps] for _ in range(a.n)] for nm, _, ps in G}
        for nm in D:
            for d in D[nm]:
                dn = torch.sqrt(sum((q.double() ** 2).sum() for q in d))
                for q in d:
                    q.div_(dn.float())
    P0 = {nm: [p.detach().clone() for p in ps] for nm, _, ps in G}
    PN = {nm: torch.sqrt(sum((q.double() ** 2).sum() for q in P0[nm])).item() for nm in P0}

    def grad(x, y, ste=None, w=None):
        for nm, mod in bas:
            assert (mod.ste, mod.w, mod.k) == orig[nm]
            if ste:
                mod._sweep = (ste, w, K)
                mod.forward = sweep_forward.__get__(mod)
        m.zero_grad(set_to_none=True)
        L = F.cross_entropy(m._net(x), y)
        L.backward()
        for nm, mod in bas:
            if ste:
                del mod.forward
        torch.cuda.empty_cache()
        return L.item(), {nm: [p.grad.detach().clone() for p in ps] for nm, _, ps in G}

    def projs(g):  # <g_G, d> per group, per direction (eps-independent; pred = eps ||p|| <g, d>)
        return {nm: [sum((gg.double() * dd.double()).sum() for gg, dd in zip(g[nm], d)).item() for d in D[nm]] for nm in g}

    K = a.k
    if a.sweep_only:
        res = json.load(open(a.sweep_only))
        x, y = batches["C"]
        sfx = f"_K{K:g}"
        res["proj"]["C_clip1_check" + sfx] = projs(grad(x, y, "clip", 1.0)[1])
        for w in WC:
            res["proj"][f"C_clip{w:g}{sfx}"] = projs(grad(x, y, "clip", w)[1])
        for w in WT:
            res["proj"][f"C_tri{w:g}{sfx}"] = projs(grad(x, y, "tri", w)[1])
        with open(a.out, "w") as f:
            json.dump(res, f)
        return
    res = dict(ckpt=a.ckpt, binact_opts=o, n=a.n, bsC=a.bsC, groups=[nm for nm, _, _ in G],
               kinds={nm: k for nm, k, _ in G}, proj={}, actual={}, L0={}, frac={})
    t0 = time.time()
    for bk, (x, y) in batches.items():
        L0, g = grad(x, y)
        res["L0"][bk] = L0
        res["proj"][f"{bk}"] = projs(g)
        print(bk, "L0", L0, "mem GB", torch.cuda.max_memory_allocated() / 1e9, f"{time.time() - t0:.0f}s", flush=True)
    x, y = batches["C"]
    res["proj"]["C_clip1_check"] = projs(grad(x, y, "clip", 1.0)[1])  # must be prop. to proj C (trained STE, K=0.6)
    for w in WC:
        res["proj"][f"C_clip{w:g}"] = projs(grad(x, y, "clip", w)[1])
    for w in WT:
        res["proj"][f"C_tri{w:g}"] = projs(grad(x, y, "tri", w)[1])
    print("sweep done", f"{time.time() - t0:.0f}s", flush=True)
    us = {}
    hs = [mod.register_forward_pre_hook(lambda mod, inp, nm=nm: us.__setitem__(
        nm, [((inp[0] - mod.t.view(1, -1, 1, 1)).abs() < w).float().mean().item() for w in WC])) for nm, mod in bas]
    with torch.no_grad():
        m._net(x)
    for h in hs:
        h.remove()
    res["frac"] = {nm: dict(zip([f"{w:g}" for w in WC], v)) for nm, v in us.items()}
    with torch.no_grad():
        for bk, (x, y) in batches.items():
            res["actual"][bk] = {}
            for nm, _, ps in G:
                rows = {}
                for eps in EPS:
                    s = eps * PN[nm]
                    act = []
                    for d in D[nm]:
                        Ls = []
                        for sg in (1, -1):
                            for p, q, dd in zip(ps, P0[nm], d):
                                p.copy_(q + sg * s * dd)
                            Ls.append(F.cross_entropy(m._net(x), y).item())
                        act.append((Ls[0] - Ls[1]) / 2)
                    for p, q in zip(ps, P0[nm]):
                        p.copy_(q)
                    rows[f"{eps:g}"] = act
                res["actual"][bk][nm] = rows
                pr = res["proj"][bk][nm]
                print(bk, nm, " ".join(f"{e}:{stats(pr, v)[0]:.2f}" for e, v in rows.items()), f"{time.time() - t0:.0f}s",
                      flush=True)
    with open(a.out, "w") as f:
        json.dump(res, f)


if __name__ == "__main__":
    main()
