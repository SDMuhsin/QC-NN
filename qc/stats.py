"""Storage and arithmetic of QC checkpoints vs dense int8:

    python -m qc.stats CKPT [CKPT ...] [--int8 DIR]   -> qc/results/<name>.md, qc/results/summary.md

<name> = the checkpoint's directory name; float test accuracy from <dir>/metrics.json ("test"); int8
test accuracy from DIR/<name>.pt (nn.quant.quantize qparams), if given.  Per conv:
  * nnz: nonzeros of the QC weight on the real input channels (conv0: 3 of the padded cin); density =
    nnz / (cout*cin*k*k).  The matrix shape is the padded GEMM matrix the blocks tile.
  * QC storage: every b x b block of the padded matrix (zero blocks included) = 2 slots x (1 valid bit +
    log2(b) shift bits [+ 1 sign bit, signed]).  Dense int8: 8 x cout*cin*k*k (cin unpadded).
  * additions per image: Hout*Wout * sum_rows max(nnz_row - 1, 0) (each output accumulates its nonzero
    terms; zero padding at the borders, which could skip terms, is ignored) vs dense multiply-adds
    Hout*Wout*cout*cin*k*k.  Per-channel scale multiplies Hout*Wout*cout are listed separately (the dense
    int8 model needs the same requant).  The FC (64x10, dense) is excluded from both.
"""
import argparse
import json
import math
import os

import torch

from nn.model.resnet8 import CONVS

from .structure import from_matrix
from .verify import load

RESULTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")
HOUT = {"conv0": 32, "conv1": 32, "conv2": 32, "conv3": 16, "conv4": 16, "conv5": 16,
        "conv6": 8, "conv7": 8, "conv8": 8}


@torch.no_grad()
def layer_stats(ck):
    model, signed = load(ck), ck["args"]["mode"] == "signed"
    rows = []
    for n, *_ in CONVS:
        conv = model.conv[n]
        M = conv.matrix()
        W = from_matrix(M, conv.cin, conv.k, conv.b, conv.view)
        cout, cin, k, _ = W.shape
        nnz_row = (W != 0).reshape(cout, -1).sum(1)
        blocks = M.shape[0] * M.shape[1] // conv.b ** 2
        hw = HOUT[n] ** 2
        dense = cout * cin * k * k
        rows.append(dict(layer=n, b=conv.b, shape=tuple(M.shape), nnz=int(nnz_row.sum()), dense=dense,
                         blocks=blocks, qc_bits=blocks * 2 * (1 + int(math.log2(conv.b)) + signed),
                         int8_bits=8 * dense, adds=hw * int((nnz_row - 1).clamp(min=0).sum()),
                         macs=hw * dense, mults=hw * cout))
    tot = {k: sum(r[k] for r in rows) for k in ("nnz", "dense", "blocks", "qc_bits", "int8_bits", "adds",
                                                 "macs", "mults")}
    return rows, tot


def table(rows, tot):
    h = ("| layer | b | matrix | nnz | density | blocks | QC bits | int8 bits | additions | dense MACs "
         "| scale mults |\n|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|\n")
    f = lambda r, name, b, shape: (f"| {name} | {b} | {shape} | {r['nnz']} | {r['nnz'] / r['dense']:.4f} | "
                                   f"{r['blocks']} | {r['qc_bits']} | {r['int8_bits']} | {r['adds']} | "
                                   f"{r['macs']} | {r['mults']} |\n")
    return h + "".join(f(r, r["layer"], r["b"], f"{r['shape'][0]}x{r['shape'][1]}") for r in rows) + \
        f(tot, "**total**", "", "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpts", nargs="+")
    ap.add_argument("--int8", default=None, help="dir with <name>.pt qparams")
    a = ap.parse_args()
    os.makedirs(RESULTS, exist_ok=True)
    summ = ["| model | b | mode | density | QC bits | int8 bits | ratio | additions | dense MACs | ratio "
            "| scale mults | float test % | int8 test % |", "|---|--:|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|"]
    for path in a.ckpts:
        name = os.path.basename(os.path.dirname(os.path.abspath(path)))
        ck = torch.load(path, map_location="cpu")
        rows, tot = layer_stats(ck)
        with open(os.path.join(os.path.dirname(path), "metrics.json")) as f:
            acc_f = 100 * json.load(f)["test"]
        acc_q = float("nan")
        if a.int8:
            acc_q = 100 * float(torch.load(os.path.join(a.int8, name + ".pt"), map_location="cpu",
                                           weights_only=False)["meta"]["acc_int8"])
        bs = sorted({r["b"] for r in rows})
        b = str(bs[0]) if len(bs) == 1 else "/".join(str(r["b"]) for r in rows)
        md = (f"# {name}: QC ResNet-8, b {b}, {ck['args']['mode']}, view {ck['args']['view']}\n\n"
              f"Checkpoint `{path}`; CIFAR-10 test: float {acc_f:.2f} %, int8 {acc_q:.2f} %.\n\n"
              + table(rows, tot) +
              f"\nQC storage / dense int8: {tot['qc_bits'] / tot['int8_bits']:.4f}; additions / dense MACs: "
              f"{tot['adds'] / tot['macs']:.4f}.  Definitions: `python -m qc.stats` docstring (additions ignore "
              f"zero-padding skips; FC excluded; conv0 nnz on the 3 real input channels, storage on the "
              f"padded blocks).\n")
        with open(os.path.join(RESULTS, name + ".md"), "w") as f:
            f.write(md)
        summ.append(f"| {name} | {b} | {ck['args']['mode']} | {tot['nnz'] / tot['dense']:.4f} | {tot['qc_bits']} | "
                    f"{tot['int8_bits']} | {tot['qc_bits'] / tot['int8_bits']:.4f} | {tot['adds']} | {tot['macs']} | "
                    f"{tot['adds'] / tot['macs']:.4f} | {tot['mults']} | {acc_f:.2f} | {acc_q:.2f} |")
        print(name, "done")
    with open(os.path.join(RESULTS, "summary.md"), "w") as f:
        f.write("# QC ResNet-8 summary (convs only; definitions in qc/stats.py)\n\n" + "\n".join(summ) + "\n")
    print("\n".join(summ))


if __name__ == "__main__":
    main()
