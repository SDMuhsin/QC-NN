"""Linear recoverability of the BinAct pre-binarisation value u from bits (measurement only).

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.diag.recover --ckpt BIN.pt --out qc18b/diag/results/recover.md

Model rebuilt with qc18b.diag.diagnose.build_bin, eval mode, fp32, TF32 off, val[:2000] (val split of qc18b.data).
Per BinAct (16): u = x - t_c (forward pre-hook input x), sigma_c = std of u over all (n, h, w) of the 2000 images.
Bits: b = 1[u > a sigma_c phi], phi = 0 (single threshold, current model), Bayer 2x2 [[-3/8, 1/8], [3/8, -1/8]] tiled by
(h mod 2, w mod 2), or iid per element uniform over {-3/8, 1/8, 3/8, -1/8} (control, torch seed 0); a in {0.5, 1, 2}.
Per channel least squares with intercept, fitted on images [0, 1000), R^2 evaluated on [1000, 2000) (R^2 = 1 - SSE/SST,
SST around the eval-set mean of u):
  R1: input = bit at the same position.
  R9: input = 9 bits of the same channel in the 3x3 neighbourhood (zero padding); dither variants (Bayer and random)
      also get the position parity (h mod 2, w mod 2) as one-hot inputs.
Normal equations accumulated in fp64, solved with pinv.  Channels with zero u variance on the eval half are excluded.
Reported per layer: mean and median over channels.
"""
import argparse
import json

import torch
import torch.nn.functional as F

from qc18b import data
from qc18b.diag.diagnose import build_bin

torch.backends.cuda.matmul.allow_tf32 = False
torch.backends.cudnn.allow_tf32 = False
N, NFIT, BS, CH = 2000, 1000, 250, 50
BAYER = [[-3 / 8, 1 / 8], [3 / 8, -1 / 8]]
AS = (0.5, 1.0, 2.0)


def feats(b, k, parity):
    """b [n, C, H, W] float {0,1} -> X [n, C, H*W, F] (intercept first)."""
    n, C, H, W = b.shape
    cols = [torch.ones_like(b)]
    if k == 1:
        cols.append(b)
    else:
        p = F.pad(b, (1, 1, 1, 1))
        cols += [p[:, :, i:i + H, j:j + W] for i in range(3) for j in range(3)]
    if parity:
        hh = torch.arange(H, device=b.device).view(H, 1) % 2
        ww = torch.arange(W, device=b.device).view(1, W) % 2
        q = (2 * hh + ww).expand(H, W)
        for v in (1, 2, 3):                                # one-hot, class 0 absorbed by the intercept
            cols.append((q == v).to(b.dtype).expand(n, C, H, W))
    return torch.stack(cols, -1).flatten(2, 3)


def r2(u, bfn, k, parity):
    """u [N, C, H, W] (cpu), bfn(u_chunk, idx) -> bits.  -> per-channel R^2 on eval half (tensor, nan if excluded)."""
    dev = "cuda"
    C = u.shape[1]
    G = Xu = None
    for i in range(0, NFIT, CH):
        uc = u[i:i + CH].to(dev)
        X = feats(bfn(uc, i), k, parity).double()
        uu = uc.double().flatten(2)
        g = torch.einsum("ncpf,ncpg->cfg", X, X)
        xu = torch.einsum("ncpf,ncp->cf", X, uu)
        G, Xu = (g, xu) if G is None else (G + g, Xu + xu)
    beta = torch.einsum("cfg,cg->cf", torch.linalg.pinv(G, hermitian=True), Xu)
    sse = torch.zeros(C, dtype=torch.float64, device=dev)
    s1 = torch.zeros_like(sse)
    s2 = torch.zeros_like(sse)
    n = 0
    for i in range(NFIT, N, CH):
        uc = u[i:i + CH].to(dev)
        X = feats(bfn(uc, i), k, parity).double()
        uu = uc.double().flatten(2)
        pred = torch.einsum("ncpf,cf->ncp", X, beta)
        sse += ((uu - pred) ** 2).sum((0, 2))
        s1 += uu.sum((0, 2))
        s2 += (uu * uu).sum((0, 2))
        n += uu.shape[0] * uu.shape[2]
    sst = s2 - s1 * s1 / n
    ok = sst > 1e-12 * n
    return torch.where(ok, 1 - sse / sst.clamp_min(1e-300), torch.full_like(sse, float("nan"))).cpu()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    dev = "cuda"
    _, (xva, yva) = data.split(dev)
    xva, yva = xva[:N], yva[:N]
    m, ck, o = build_bin(a.ckpt, dev)
    m.eval()
    acts = m.binacts()
    U = {n: [] for n, _ in acts}
    hs = [ba.register_forward_pre_hook(lambda mod, inp, n=n: U[n].append((inp[0] - mod.t.view(1, -1, 1, 1)).float().cpu())) for n, ba in acts]
    correct = 0
    with torch.no_grad():
        for i in range(0, N, BS):
            correct += (m(data.prep(xva[i:i + BS])).argmax(1) == yva[i:i + BS]).sum().item()
    for h in hs:
        h.remove()
    acc = correct / N
    print(f"val[:{N}] acc {acc:.4f}", flush=True)
    rows = []
    with torch.no_grad():
        for n, _ in acts:
            u = torch.cat(U[n]).contiguous()
            U[n] = None
            _, C, H, W = u.shape
            sig = u.double().transpose(0, 1).reshape(C, -1).std(1, unbiased=False).float().to(dev).view(1, C, 1, 1)
            bay = torch.tensor(BAYER, device=dev).repeat((H + 1) // 2, (W + 1) // 2)[:H, :W].view(1, 1, H, W)
            g = torch.Generator(device="cpu").manual_seed(0)
            vals = torch.tensor([-3 / 8, 1 / 8, 3 / 8, -1 / 8])
            rnd = vals[torch.randint(0, 4, tuple(u.shape), generator=g)]          # [N, C, H, W] cpu
            border = 1.0 if min(H, W) <= 2 else (H * W - (H - 2) * (W - 2)) / (H * W)
            r = dict(layer=n, C=C, H=H, W=W, border=border, frac_pos=(u > 0).float().mean().item())
            single = lambda uc, i: (uc > 0).float()
            for k in (1, 9):
                r[f"single_R{k}"] = r2(u, single, k, False)
            for aa in AS:
                bf = lambda uc, i, aa=aa: (uc > aa * sig * bay).float()
                rf = lambda uc, i, aa=aa: (uc > aa * sig * rnd[i:i + uc.shape[0]].to(dev)).float()
                for k in (1, 9):
                    r[f"bayer{aa}_R{k}"] = r2(u, bf, k, k == 9)
                    r[f"rand{aa}_R{k}"] = r2(u, rf, k, k == 9)
            out = {}
            for key, v in list(r.items()):
                if torch.is_tensor(v):
                    vv = v[~v.isnan()]
                    out[key] = dict(mean=vv.mean().item(), median=vv.median().item(), excl=int(v.isnan().sum()))
                else:
                    out[key] = v
            rows.append(out)
            print(n, H, W, " ".join(f"{k}={v['mean']:.3f}" for k, v in out.items() if isinstance(v, dict)), flush=True)
            del u, rnd
            torch.cuda.empty_cache()
    with open(a.out.replace(".md", ".json"), "w") as fh:
        json.dump(dict(ckpt=a.ckpt, acc=acc, rows=rows), fh, indent=1)
    write_md(rows, acc, a.ckpt, a.out)


def write_md(rows, acc, ckpt, path):
    md = lambda v: sorted(v)[len(v) // 2 - 1] / 2 + sorted(v)[len(v) // 2] / 2
    L = ["# recover: linear recoverability of u = x - t_c from bits (qc18b/diag/recover.py)", "",
         f"Model {ckpt}, eval, fp32, val[:2000] (acc {100 * acc:.2f}).  Measured.  " + __doc__.split("\n\n", 1)[1].strip()
         .replace("\n", " "), "",
         "## Per layer, single threshold b = 1[u > 0] (R^2 mean / median over channels)", "",
         "| layer | C | HxW | border frac | p(u>0) | R1 mean | R1 median | R9 mean | R9 median | excl ch |",
         "|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        s1, s9 = r["single_R1"], r["single_R9"]
        L.append(f"| {r['layer']} | {r['C']} | {r['H']}x{r['W']} | {r['border']:.3f} | {r['frac_pos']:.3f} | {s1['mean']:.4f} | "
                 f"{s1['median']:.4f} | {s9['mean']:.4f} | {s9['median']:.4f} | {s1['excl']} |")
    for k in (1, 9):
        L += ["", f"## Per layer R{k}, mean over channels (median in parentheses)", "",
              "| layer | single | " + " | ".join(f"Bayer a={aa} | rand a={aa}" for aa in AS) + " |",
              "|---|---|" + "---|---|" * len(AS)]
        for r in rows:
            c = lambda key: f"{r[key]['mean']:.4f} ({r[key]['median']:.4f})"
            L.append(f"| {r['layer']} | {c(f'single_R{k}')} | " + " | ".join(f"{c(f'bayer{aa}_R{k}')} | {c(f'rand{aa}_R{k}')}" for aa in AS) + " |")
    L += ["", "## Over layers: median over the 16 layers of the per-layer channel-mean R^2", "",
          "| variant | R1 | R9 | R9 - single R9 (median over layers of per-layer difference) |", "|---|---|---|---|"]
    keys = ["single"] + [f"{p}{aa}" for aa in AS for p in ("bayer", "rand")]
    for kk in keys:
        d = [r[f"{kk}_R9"]["mean"] - r["single_R9"]["mean"] for r in rows]
        L.append(f"| {kk} | {md([r[f'{kk}_R1']['mean'] for r in rows]):.4f} | {md([r[f'{kk}_R9']['mean'] for r in rows]):.4f} | {md(d):+.4f} |")
    L += ["", "## Bayer R9 - single R9 per layer (channel-mean R^2)", "", "| layer | " + " | ".join(f"a={aa}" for aa in AS) + " |",
          "|---|" + "---|" * len(AS)]
    for r in rows:
        L.append(f"| {r['layer']} | " + " | ".join(f"{r[f'bayer{aa}_R9']['mean'] - r['single_R9']['mean']:+.4f}" for aa in AS) + " |")
    with open(path, "w") as fh:
        fh.write("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
