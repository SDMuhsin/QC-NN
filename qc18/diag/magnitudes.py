"""M3: hard net vs real-magnitude net at a checkpoint.

    python3 -m qc18.diag.magnitudes CKPT [CKPT ...] --out JSON

(i) hard: stored v.  (ii) same mask and signs, kept values = z = theta / alpha_r (the real latent ratio; nonzero
only where v != 0).  Both: BN recalibrated on train[:10000] (unaugmented, as in train/verify), val accuracy fp32.
Also the deciles (0, 0.1, ..., 1) of |z| over all kept coefficients.
"""
import argparse
import json

import torch

from ..data import split
from ..qcconv import row_alpha
from ..train import accuracy, recal_bn
from .common import load


@torch.no_grad()
def run(path):
    ck, model = load(path)
    (xtr, _), (xva, yva) = split("cuda")
    convs = model.qconvs()
    hard_v = [c.v.clone() for c in convs]
    stored = accuracy(model, xva, yva)
    recal_bn(model, xtr[:10000])
    acc_hard = accuracy(model, xva, yva)
    zs = []
    for c, v in zip(convs, hard_v):
        z = c.theta / row_alpha(c.theta)
        keep = v != 0
        assert (torch.sign(z[keep]) == v[keep]).all()
        c.v.copy_(torch.where(keep, z, torch.zeros_like(z)))
        zs.append(z[keep].abs().flatten())
    recal_bn(model, xtr[:10000])
    acc_z = accuracy(model, xva, yva)
    za = torch.cat(zs).double()
    q = torch.linspace(0, 1, 11, dtype=torch.float64, device=za.device)
    return dict(ckpt=path, epoch=ck["epoch"] + 1, val_ckpt=ck["val"], val_stored_bn=stored, val_hard=acc_hard,
                val_z=acc_z, n_kept=len(za), absz_quantiles=dict(zip([round(x, 1) for x in q.tolist()],
                                                                     torch.quantile(za.float(), q.float()).tolist())),
                absz_mean=za.mean().item())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="+")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    out = [run(p) for p in a.ckpts]
    for r in out:
        print(json.dumps({k: v for k, v in r.items()}))
    with open(a.out, "w") as f:
        json.dump(out, f, indent=1)


if __name__ == "__main__":
    main()
