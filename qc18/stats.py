"""Storage and arithmetic of qc18 QC checkpoints vs dense int8:

    python3 -m qc18.stats RUN [RUN ...]   (RUN = /tmp/$USER/qc18/final/<NAME>_s<SEED>)
        -> qc18/results/<NAME>_s<SEED>.md, qc18/results/summary.md (one row per RUN given)

Accuracies: float test from RUN/verify.txt (folded fp64 QC network), int8 val/test from RUN/int8.txt (qc18.int8).
Per conv (stem, block convs, 1x1 shortcuts; the dense 512x10 FC is excluded everywhere):
  * nnz on the real input channels (stem: 3 of the padded cin); density = nnz / (cout*cin*k*k).
  * QC storage: every b x b block of the padded GEMM matrix (zero blocks included) = 2 slots x (1 valid bit +
    log2(b) shift bits [+ 1 sign bit, signed]).  Dense int8: 8 bits x cout*cin*k*k (cin unpadded).
    Per-channel scales/biases (same for both) are not counted.
  * additions per image: Hout*Wout * sum_rows max(nnz_row - 1, 0) (border zero-padding skips ignored) vs
    dense multiply-accumulates Hout*Wout*cout*cin*k*k.
"""
import argparse
import math
import os
import re

import torch

from qc.structure import from_matrix

from .verify import load

RESULTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")


def grab(path, pattern):
    try:
        m = re.search(pattern, open(path).read())
    except FileNotFoundError:
        return float("nan")
    return float(m.group(1)) if m else float("nan")


@torch.no_grad()
def layer_stats(model, signed):
    hw = {}
    hooks = [cb.conv.register_forward_hook(lambda m, i, o, n=n: hw.__setitem__(n, o.shape[2] * o.shape[3]))
             for n, cb in model.convbns()]
    model(torch.zeros(1, 3, 32, 32))
    for h in hooks:
        h.remove()
    rows = []
    for n, cb in model.convbns():
        conv = cb.conv
        M = conv.matrix()
        W = from_matrix(M, conv.cin, conv.k, conv.b)
        cout, cin, k, _ = W.shape
        nnz_row = (W != 0).reshape(cout, -1).sum(1)
        blocks = M.shape[0] * M.shape[1] // conv.b ** 2
        dense = cout * cin * k * k
        rows.append(dict(layer=n, b=conv.b, shape=tuple(M.shape), hw=hw[n], nnz=int(nnz_row.sum()), dense=dense,
                         blocks=blocks, qc_bits=blocks * 2 * (1 + int(math.log2(conv.b)) + signed),
                         int8_bits=8 * dense, adds=hw[n] * int((nnz_row - 1).clamp(min=0).sum()),
                         macs=hw[n] * dense))
    tot = {k: sum(r[k] for r in rows) for k in ("nnz", "dense", "blocks", "qc_bits", "int8_bits", "adds", "macs")}
    return rows, tot


def table(rows, tot):
    h = ("| layer | matrix | Hout*Wout | nnz | density | blocks | QC bits | int8 bits | additions | dense MACs |\n"
         "|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|\n")
    f = lambda r, name, shape, hw: (f"| {name} | {shape} | {hw} | {r['nnz']} | {r['nnz'] / r['dense']:.4f} | "
                                    f"{r['blocks']} | {r['qc_bits']} | {r['int8_bits']} | {r['adds']} | {r['macs']} |\n")
    return h + "".join(f(r, r["layer"], f"{r['shape'][0]}x{r['shape'][1]}", r["hw"]) for r in rows) + \
        f(tot, "**total**", "", "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+")
    a = ap.parse_args()
    os.makedirs(RESULTS, exist_ok=True)
    summ = ["| model | mode | b | density | QC Mbit | int8 Mbit | storage ratio | additions (M) | dense MACs (M) "
            "| adds ratio | float test % | int8 val % | int8 test % |",
            "|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|"]
    for run in a.runs:
        run = os.path.abspath(run.rstrip("/"))
        name = os.path.basename(run)
        ck, model = load(os.path.join(run, "best.pt"), "cpu")
        mode, b = ck["args"]["mode"], ck["args"]["b"]
        rows, tot = layer_stats(model, mode == "signed")
        acc_f = grab(os.path.join(run, "verify.txt"), r"test accuracy: folded QC network \(fp64\) ([\d.]+) %")
        acc_v = grab(os.path.join(run, "int8.txt"), r"val accuracy: .*int8 ([\d.]+) %")
        acc_q = grab(os.path.join(run, "int8.txt"), r"test accuracy: int8 ([\d.]+) %")
        rs, ra = tot["qc_bits"] / tot["int8_bits"], tot["adds"] / tot["macs"]
        md = (f"# {name}: QC ResNet-18 (CIFAR-10), {mode}, b {b}\n\n"
              f"Checkpoint `{run}/best.pt` (epoch {ck['epoch']}); test: float {acc_f:.2f} %, int8 {acc_q:.2f} % "
              f"(int8 val {acc_v:.2f} %).\n\n" + table(rows, tot) +
              f"\nQC storage / dense int8: {rs:.4f}; additions / dense MACs: {ra:.4f}.  Definitions: "
              f"`qc18/stats.py` docstring (convs only, FC excluded; stem nnz on the 3 real input channels, "
              f"storage on the padded blocks).\n")
        with open(os.path.join(RESULTS, name + ".md"), "w") as f:
            f.write(md)
        summ.append(f"| {name} | {mode} | {b} | {tot['nnz'] / tot['dense']:.4f} | {tot['qc_bits'] / 1e6:.3f} | "
                    f"{tot['int8_bits'] / 1e6:.3f} | {rs:.4f} | {tot['adds'] / 1e6:.1f} | {tot['macs'] / 1e6:.1f} | "
                    f"{ra:.4f} | {acc_f:.2f} | {acc_v:.2f} | {acc_q:.2f} |")
        print(name, "done")
    with open(os.path.join(RESULTS, "summary.md"), "w") as f:
        f.write("# QC ResNet-18 summary (convs only, FC excluded; definitions in qc18/stats.py, int8 scheme in "
                "qc18/int8.py)\n\n" + "\n".join(summ) + "\n")
    print("\n".join(summ))


if __name__ == "__main__":
    main()
