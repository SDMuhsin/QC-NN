"""Fold BN into every QC conv and export the float params in the nn/model load_h5 format.

    python -m qc.export CKPT --out /tmp/$USER/qc/export/NAME.npz

Per conv: W[cout, cin, k, k] = scale[co] * M (M = the exact 0/1 or -1/0/1 QC matrix, padded input
channels dropped), b = BN bias (scale = gamma / sqrt(var + eps)); "fc": the dense float layer (applied
to the 8x8 average pool, as in nn/model).  Saved as .npz with keys "<layer>.W", "<layer>.b"
(read back with nn.quant.quantize.load_params, or `python -m nn.quant.quantize --params PATH`).
"""
import argparse
import os

import numpy as np
import torch

from nn.model.resnet8 import CONVS

from .structure import from_matrix
from .verify import fold, load

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


@torch.no_grad()
def export(ck):
    model = load(ck)
    params = {}
    for n, *_ in CONVS:
        conv = model.conv[n]
        M = from_matrix(conv.matrix(), conv.cin, conv.k, conv.b, conv.view)
        scale, bias = fold(model.bn[n])
        params[n] = ((scale[:, None, None, None] * M).numpy(), bias.numpy())
    params["fc"] = (model.fc.weight.numpy(), model.fc.bias.numpy())
    return params


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--out", required=True, help=".npz outside the repo")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    assert not out.startswith(REPO + os.sep), "--out must be outside the repo"
    params = export(torch.load(a.ckpt, map_location="cpu"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    np.savez(out, **{f"{k}.{p}": v for k, (W, b) in params.items() for p, v in (("W", W), ("b", b))})
    print("wrote", out)


if __name__ == "__main__":
    main()
