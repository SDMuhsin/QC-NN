"""Markdown table of the final qc18 runs (CPU only):

    python3 -m qc18.table [FINAL_DIR]   (default /tmp/$USER/qc18/final; every <NAME>_s<SEED>/ with verify.txt)

Columns: best val (metrics.json), verified folded test (verify.txt; fp32 test for dense), int8 test (int8.txt),
storage and additions ratios vs dense int8 (qc18/results/<run>.md if present, else qc18.stats.layer_stats).
A mean +- std (over seeds, sample std) row follows each model with >= 2 seeds.
"""
import getpass
import json
import os
import re
import statistics
import sys

from .stats import RESULTS, grab


def ratios(run, name, mode):
    if mode == "dense":
        return float("nan"), float("nan")
    md = os.path.join(RESULTS, name + ".md")
    if os.path.exists(md):
        m = re.search(r"QC storage / dense int8: (\d+\.\d+); additions / dense MACs: (\d+\.\d+)", open(md).read())
        if m:
            return float(m.group(1)), float(m.group(2))
    from .stats import layer_stats
    from .verify import load
    ck, model = load(os.path.join(run, "best.pt"), "cpu")
    _, tot = layer_stats(model, mode == "signed")
    return tot["qc_bits"] / tot["int8_bits"], tot["adds"] / tot["macs"]


def fmt(x, d=2):
    return "-" if x != x else f"{x:.{d}f}"


def ms(xs, d=2):
    xs = [x for x in xs if x == x]
    if not xs:
        return "-"
    return f"{statistics.mean(xs):.{d}f} ± {statistics.stdev(xs):.{d}f}" if len(xs) > 1 else f"{xs[0]:.{d}f}"


def main():
    F = sys.argv[1] if len(sys.argv) > 1 else f"/tmp/{os.environ.get('USER') or getpass.getuser()}/qc18/final"
    runs = {}
    for name in sorted(os.listdir(F)):
        run = os.path.join(F, name)
        m = re.fullmatch(r"(.+)_s(\d+)", name)
        if not (m and os.path.isdir(run) and os.path.exists(os.path.join(run, "verify.txt"))):
            continue
        a = json.load(open(os.path.join(run, "metrics.json")))
        mode = a["args"]["mode"]
        v = os.path.join(run, "verify.txt")
        test = grab(v, r"test accuracy \(fp32\) ([\d.]+) %" if mode == "dense"
                    else r"test accuracy: folded QC network \(fp64\) ([\d.]+) %")
        rs, ra = ratios(run, name, mode)
        runs.setdefault(m.group(1), []).append(dict(
            seed=int(m.group(2)), mode=mode, b="-" if mode == "dense" else a["args"]["b"],
            val=100 * a["best_val"], test=test, int8=grab(os.path.join(run, "int8.txt"), r"test accuracy: int8 ([\d.]+) %"),
            rs=rs, ra=ra))
    out = ["| model | strict/signed | b | seed | best val % | verified test % | int8 test % | storage ratio | adds ratio |",
           "|---|---|--:|--:|--:|--:|--:|--:|--:|"]
    for model, rr in runs.items():
        rr.sort(key=lambda r: r["seed"])
        for r in rr:
            out.append(f"| {model} | {r['mode']} | {r['b']} | {r['seed']} | {fmt(r['val'])} | {fmt(r['test'])} | "
                       f"{fmt(r['int8'])} | {fmt(r['rs'], 4)} | {fmt(r['ra'], 4)} |")
        if len(rr) > 1:
            g = lambda k, d=2: ms([r[k] for r in rr], d)
            out.append(f"| **{model} mean ± std** | {rr[0]['mode']} | {rr[0]['b']} | n={len(rr)} | {g('val')} | "
                       f"{g('test')} | {g('int8')} | {g('rs', 4)} | {g('ra', 4)} |")
    print("\n".join(out))


if __name__ == "__main__":
    main()
