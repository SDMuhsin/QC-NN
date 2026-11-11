"""Tables for the binary-activation pilot (qc18b.train_bin runs) -> qc18b/diag/results/gradflow_pilot.md.
    python3 -m qc18b.diag.gradflow_table [--root /tmp/$USER/qc18b/pilot] [--runs fp60,bin_scratch,...]
Per run: best val / epoch, median s/epoch, train acc + loss at epochs 1/10/30/60 (1-based).  Per BinAct layer and
per QCConv2d at those epochs: means over that epoch's gradflow.jsonl records."""
import argparse
import getpass
import json
import os
from collections import defaultdict

EPOCHS = (1, 10, 30, 60)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", "gradflow_pilot.md")


def load(run):
    m = json.load(open(os.path.join(run, "metrics.json")))
    g = defaultdict(list)                        # (kind, layer, epoch 1-based) -> records
    p = os.path.join(run, "gradflow.jsonl")
    if os.path.exists(p):
        for line in open(p):
            r = json.loads(line)
            g[r["kind"], r["layer"], r["epoch"] + 1].append(r)
    return m, g


def mean(rs, f):
    v = [f(r) for r in rs]
    return sum(v) / len(v) if v else float("nan")


def ratio(rs):
    """mean ||g_in|| / ||g_out|| over records with g_out > 0; '0/0' if g_out == 0 in every record."""
    nz = [x for x in rs if x["g_out"] > 0]
    s = f"{mean(nz, lambda x: x['g_in'] / x['g_out']):.3f}" if nz else "0/0"
    return s + (f" ({len(rs) - len(nz)}/{len(rs)} gout=0)" if nz and len(nz) < len(rs) else "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=f"/tmp/{getpass.getuser()}/qc18b/pilot")
    ap.add_argument("--runs", default="fp60,bin_scratch,bin_init,bin_scratch_approx")
    a = ap.parse_args()
    runs = [r for r in a.runs.split(",") if os.path.exists(os.path.join(a.root, r, "metrics.json"))]
    data = {r: load(os.path.join(a.root, r)) for r in runs}
    L = ["# Binary-activation pilot: grad flow (measured)", "",
         f"Source: {a.root}/<run>/metrics.json, gradflow.jsonl (one record per BinAct / QCConv2d every 50 training "
         "steps; epoch values = mean over that epoch's records). BinAct cells: p1 = mean(b), const = frac. channels with "
         "mean(b) < 0.01 or > 0.99, pass = frac. |x - t| < w, gin/gout = ||dL/dx|| / ||dL/db|| (mean over records with "
         "gout > 0; '0/0': gout exactly 0 in every record), gout = ||dL/db||. "
         "Val = 5k held-out split, BN recalibrated. Epochs 1-based.",
         "", "## Runs", "",
         "| run | best val | best ep | s/epoch (median train) | " +
         " | ".join(f"train acc / loss ep{e}" for e in EPOCHS) + " |",
         "|---|---|---|---|" + "---|" * len(EPOCHS)]
    for r, (m, _) in data.items():
        h = m["history"]
        cells = [f"{100 * h[e - 1]['train_acc']:.2f} / {h[e - 1]['loss']:.3f}" if e <= len(h) else "-" for e in EPOCHS]
        L.append(f"| {r} | {100 * m['best_val']:.2f} | {m['best_epoch'] + 1} | {m['epoch_sec_median']:.1f} | "
                 + " | ".join(cells) + " |")
    for r, (m, g) in data.items():
        layers = sorted({k[1] for k in g if k[0] == "binact"}, key=lambda s: (int(s.split(".")[1]), s))
        if layers:
            L += ["", f"## {r}: BinAct layers", "",
                  "| layer | " + " | ".join(f"ep{e} p1 / const / pass / gin/gout / gout" for e in EPOCHS) + " |",
                  "|---|" + "---|" * len(EPOCHS)]
            for ly in layers:
                c = []
                for e in EPOCHS:
                    rs = g.get(("binact", ly, e), [])
                    c.append("-" if not rs else
                             f"{mean(rs, lambda x: x['p1']):.3f} / {mean(rs, lambda x: x['const']):.3f} / "
                             f"{mean(rs, lambda x: x['pass']):.3f} / "
                             f"{ratio(rs)} / {mean(rs, lambda x: x['g_out']):.3g}")
                L.append(f"| {ly} | " + " | ".join(c) + " |")
            bad = sum(1 for k, rs in g.items() if k[0] == "binact" for x in rs if not x["exact01"])
            L.append(f"\nrecords with b not exactly in {{0,1}}: {bad}")
        convs = [k for k in dict.fromkeys(k[1] for k in g if k[0] == "conv")]
        if convs:
            convs.sort(key=lambda s: (s != "stem.conv", int(s.split(".")[1]) if s.startswith("blocks") else -1, s))
            L += ["", f"## {r}: per-conv ||grad theta||", "",
                  "| conv | " + " | ".join(f"ep{e}" for e in EPOCHS) + " |", "|---|" + "---|" * len(EPOCHS)]
            for cv in convs:
                c = [f"{mean(g[('conv', cv, e)], lambda x: x['g_theta']):.4g}" if g.get(("conv", cv, e)) else "-"
                     for e in EPOCHS]
                L.append(f"| {cv} | " + " | ".join(c) + " |")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w").write("\n".join(L) + "\n")
    print(f"-> {OUT}")


if __name__ == "__main__":
    main()
