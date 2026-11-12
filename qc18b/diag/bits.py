"""Per-BinAct information / redundancy of binary activations (measurement only).

    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.diag.bits --ckpt A.pt [B.pt ...] --out qc18b/diag/results/bits.md

Model rebuilt from the checkpoint's args + first line of its train.log (diag.fidelity.build), eval mode, fp32, TF32
off, 5k val images.  For each BinAct (input x = FP pre-activation feeding it, output b = 1[x > t_c]), over all
(n, h, w) positions: p1_c = mean(b_c), H_c = binary entropy of p1_c (bits); mean_c H, frac. channels H < 0.1.
Redundancy (for b and for x; per-channel shift u = x - t_c leaves both unchanged): channel covariance S (fp64,
exact over all positions); |corr| mean over 256 random channel pairs i != j (seed 0; pairs with a zero-variance
channel excluded and counted); effective rank = exp(entropy of eigenvalues of S / trace).
"""
import argparse
import math

import torch

from qc18b import binact, data
from qc18b.diag.fidelity import build

torch.backends.cuda.matmul.allow_tf32 = False
torch.backends.cudnn.allow_tf32 = False


class Acc:
    def __init__(self, C, dev):
        self.n, self.s, self.ss = 0, torch.zeros(C, dtype=torch.float64, device=dev), torch.zeros(C, C, dtype=torch.float64, device=dev)

    def add(self, X):                                   # X [N, C, H, W]
        R = X.detach().double().permute(0, 2, 3, 1).reshape(-1, X.shape[1])
        self.n += R.shape[0]
        self.s += R.sum(0)
        self.ss += R.T @ R

    def stats(self, pairs):
        m = self.s / self.n
        S = self.ss / self.n - torch.outer(m, m)
        v = S.diagonal().clamp_min(0)
        i, j = pairs
        ok = (v[i] > 0) & (v[j] > 0)
        corr = (S[i, j] / (v[i] * v[j]).sqrt())[ok].abs()
        ev = torch.linalg.eigvalsh(S).clamp_min(0)
        p = ev / ev.sum()
        er = math.exp(-(p[p > 0] * p[p > 0].log()).sum().item())
        return dict(m=m, corr=corr.mean().item(), bad=int((~ok).sum()), erank=er)


def pairs_for(C, dev, k=256):
    g = torch.Generator().manual_seed(0)
    i = torch.randint(0, C, (k,), generator=g)
    j = (i + torch.randint(1, C, (k,), generator=g)) % C
    return i.to(dev), j.to(dev)


@torch.no_grad()
def measure(ckpt, dev, xva, yva, bs=250):
    m, a, o = build(ckpt, dev)
    m.eval()
    acts = m.binacts()
    accs = {n: (Acc(ba.t.numel(), dev), Acc(ba.t.numel(), dev)) for n, ba in acts}
    hs = [ba.register_forward_hook(lambda mod, inp, out, n=n: [accs[n][0].add(out), accs[n][1].add(inp[0])] and None) for n, ba in acts]
    correct = 0
    for i in range(0, len(xva), bs):
        correct += (m(data.prep(xva[i:i + bs])).argmax(1) == yva[i:i + bs]).sum().item()
    for h in hs:
        h.remove()
    rows = []
    for n, ba in acts:
        P = pairs_for(ba.t.numel(), dev)
        sb, sx = accs[n][0].stats(P), accs[n][1].stats(P)
        p = sb["m"].clamp(0, 1)
        H = torch.where((p > 0) & (p < 1), -(p * p.clamp_min(1e-300).log2() + (1 - p) * (1 - p).clamp_min(1e-300).log2()), torch.zeros_like(p))
        rows.append(dict(layer=n, C=ba.t.numel(), H=H.mean().item(), low=(H < 0.1).float().mean().item(),
                         corr_b=sb["corr"], corr_u=sx["corr"], bad_b=sb["bad"], bad_u=sx["bad"],
                         er_b=sb["erank"], er_u=sx["erank"]))
    return rows, correct / len(xva), a["epochs"], torch.load(ckpt, map_location="cpu", weights_only=False)["val"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    dev = "cuda"
    _, (xva, yva) = data.split(dev)
    L = ["# bits: per-BinAct entropy / channel redundancy (qc18b/diag/bits.py)", "",
         "eval mode, fp32, 5k val images, all (n, h, w) positions.  H = mean over channels of binary entropy of p1_c (bits); "
         "low = frac. channels H < 0.1; |corr| = mean over 256 random channel pairs (pairs with a constant channel excluded, "
         "count in 'excl'); erank = exp(entropy of normalised covariance eigenvalues); b = BinAct output, u = FP pre-activation "
         "input of that BinAct.", ""]
    for ck in a.ckpt:
        rows, acc, ep, sval = measure(ck, dev, xva, yva)
        L += [f"## {ck}", "", f"rebuilt model val acc {100 * acc:.2f} (saved val {100 * sval:.2f}; run epochs {ep})", "",
              "| layer | C | mean H (bits) | low H<0.1 | \\|corr\\| b | \\|corr\\| u | excl b/u | erank b | erank u | erank b/u |",
              "|---|---|---|---|---|---|---|---|---|---|"]
        for r in rows:
            L.append(f"| {r['layer']} | {r['C']} | {r['H']:.3f} | {r['low']:.3f} | {r['corr_b']:.3f} | {r['corr_u']:.3f} | "
                     f"{r['bad_b']}/{r['bad_u']} | {r['er_b']:.1f} | {r['er_u']:.1f} | {r['er_b'] / r['er_u']:.3f} |")
        f = lambda k: sorted(r[k] for r in rows)
        rat = sorted(r["er_b"] / r["er_u"] for r in rows)
        md = lambda v: (v[len(v) // 2 - 1] + v[len(v) // 2]) / 2
        L += ["", f"range over {len(rows)} layers (min / median / max): mean H {f('H')[0]:.3f} / {md(f('H')):.3f} / {f('H')[-1]:.3f}; "
              f"erank b/u {rat[0]:.3f} / {md(rat):.3f} / {rat[-1]:.3f}; |corr| b {f('corr_b')[0]:.3f} / {md(f('corr_b')):.3f} / {f('corr_b')[-1]:.3f}; "
              f"|corr| u {f('corr_u')[0]:.3f} / {md(f('corr_u')):.3f} / {f('corr_u')[-1]:.3f}", ""]
        print("\n".join(L[-len(rows) - 6:]), flush=True)
    with open(a.out, "w") as fh:
        fh.write("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
