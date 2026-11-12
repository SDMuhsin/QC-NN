"""Inference signed-addition count per QC conv of a qc18b checkpoint, grouped per block:

    python3 -m qc18b.opcount CKPT

Counting = qc18.stats.layer_stats (imported): per conv, from the hard v (conv.matrix()),
additions = Hout*Wout * sum_rows max(nnz_row - 1, 0); terms = Hout*Wout * nnz (nonzero +-1 terms x output positions).
Convs only (stem, block convs, 1x1 shortcuts; FC excluded).  Shares are of the network total additions.
Activations (BinAct / ReLU) do not change the conv shapes, so the plain qc18 QCResNet18 (100 classes) is built and the
BinAct parameters (b1 / b2) are dropped from the state dict.
"""
import argparse
import re

import torch

from qc18.model import QCResNet18
from qc18.stats import layer_stats

from . import data


def load(path):
    ck = torch.load(path, map_location="cpu")
    a = ck["args"]
    model = QCResNet18(a["mode"], a["b"], a["estimator"], a["tau0"], num_classes=data.NUM_CLASSES)
    sd = {k: v for k, v in ck["state"].items() if not re.search(r"\.b[12]\.", k)}
    model.load_state_dict(sd)
    return ck, model.eval()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    a = ap.parse_args()
    ck, model = load(a.ckpt)
    rows, tot = layer_stats(model, ck["args"]["mode"] == "signed")
    cio = {n: (cb.conv.cin, cb.conv.cout, cb.conv.k) for n, cb in model.convbns()}
    hw = {}
    hooks = [cb.conv.register_forward_hook(lambda m, i, o, n=n: hw.__setitem__(n, tuple(o.shape[2:])))
             for n, cb in model.convbns()]
    with torch.no_grad():
        model(torch.zeros(1, 3, 32, 32))
    for h in hooks:
        h.remove()
    print(f"{a.ckpt} (epoch {ck['epoch']}, val {100 * ck['val']:.2f}); total additions {tot['adds'] / 1e6:.2f} M, "
          f"terms {sum(r['nnz'] * r['hw'] for r in rows) / 1e6:.2f} M")
    print(f"{'conv':<18}{'cin':>5}{'cout':>5}{'k':>3}{'HxW':>8}{'additions':>12}{'terms':>12}{'share %':>9}")
    grp = {}
    for r in rows:
        n = r["layer"]
        cin, cout, k = cio[n]
        g = n.split(".")[1] if n.startswith("blocks.") else n.split(".")[0]
        grp.setdefault(g, [0, 0])
        grp[g][0] += r["adds"]
        grp[g][1] += r["nnz"] * r["hw"]
        print(f"{n:<18}{cin:>5}{cout:>5}{k:>3}{'%dx%d' % hw[n]:>8}{r['adds']:>12}{r['nnz'] * r['hw']:>12}"
              f"{100 * r['adds'] / tot['adds']:>9.2f}")
    print(f"\n{'block':<8}{'additions':>12}{'share %':>9}")
    for g, (ad, te) in grp.items():
        print(f"{g:<8}{ad:>12}{100 * ad / tot['adds']:>9.2f}")
    print("compact: " + "  ".join(f"{g}: {100 * v[0] / tot['adds']:.1f}" for g, v in grp.items()))


if __name__ == "__main__":
    main()
