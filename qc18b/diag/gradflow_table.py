"""Tables for the binary-activation pilot (qc18b.train_bin runs) -> qc18b/diag/results/gradflow_pilot.md.
    python3 -m qc18b.diag.gradflow_table [--root /tmp/$USER/qc18b/pilot] [--runs fp60,bin_scratch,...]
    python3 -m qc18b.diag.gradflow_table --gain 1 --root /tmp/$USER/qc18b/gain --runs clip,clip_tfrozen,...
    python3 -m qc18b.diag.gradflow_table --pre 1 --root /tmp/$USER/qc18b/pre --runs F30,PK43,PK30,PK60
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


def snapshots(rd, eps):
    """-> metrics, [(name, step)] for step 50 and the last record of epochs eps (1-based), {step: {layer: record}}."""
    m = json.load(open(os.path.join(rd, "metrics.json")))
    recs = [json.loads(x) for x in open(os.path.join(rd, "gradflow.jsonl"))]
    steps = sorted({x["step"] for x in recs})
    last = {e: max([s for s in steps if (s - 1) // 351 == e - 1], default=None) for e in eps}
    by = defaultdict(dict)
    for x in recs:
        by[x["step"]][x["layer"]] = x
    return m, [("s50", 50)] + [(f"ep{e}", last[e]) for e in eps], by


def pre(root, runs):
    """-> gradflow_pre.md: pre-ReLU b1 runs; b1 / b2 layer means at step 50 and the end of epochs 1/10/30."""
    eps = (1, 10, 30)
    L = ["# Pre-ReLU b1 (--preact 1) runs (measured)", "",
         f"Source: {root}/<run>/metrics.json, gradflow.jsonl (records every 50 steps, 351 steps/epoch). Snapshot "
         "'s50' = the step-50 record; 'epE' = the last record of epoch E (1-based). const / pass / p1 = mean over the 8 "
         "b1 (blocks.k.b1) or the 8 b2 layers. g0/g7 = g_out(blocks.0.b1) / g_out(blocks.7.b2). b1/b2 = mean over k of "
         "g_out(blocks.k.b1) / g_out(blocks.k.b2). BN: max |beta|, max gamma over all BatchNorm2d. Val = 5k held-out "
         "split. '-' = no BinAct (F30).", "",
         "| run | best val | best ep | " + " | ".join(f"train ep{e}" for e in eps) + " |", "|---|---|---|" + "---|" * len(eps)]
    S = ["", "| run | snap | step | b1 const | b1 pass | b1 p1 | b2 const | b2 pass | b2 p1 | g0/g7 | b1/b2 | "
         "BN max abs beta | BN max gamma |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in runs:
        m, pick, by = snapshots(os.path.join(root, r), eps)
        h = m["history"]
        L.append(f"| {r} | {100 * m['best_val']:.2f} | {m['best_epoch'] + 1} | "
                 + " | ".join(f"{100 * h[e - 1]['train_acc']:.2f}" if e <= len(h) else "-" for e in eps) + " |")
        for nm, st in pick:
            d = by.get(st, {})
            c = []
            for b in ("b1", "b2"):
                ks = [f"blocks.{k}.{b}" for k in range(8) if f"blocks.{k}.{b}" in d]
                c += [f"{sum(d[k][f] for k in ks) / len(ks):.3f}" if ks else "-" for f in ("const", "pass", "p1")]
            if "blocks.0.b1" in d:
                c.append(f"{d['blocks.0.b1']['g_out'] / d['blocks.7.b2']['g_out']:.3g}")
                rt = [d[f"blocks.{k}.b1"]["g_out"] / d[f"blocks.{k}.b2"]["g_out"] for k in range(8)]
                c.append(f"{sum(rt) / len(rt):.3f}")
            else:
                c += ["-", "-"]
            bn = d.get("bn", {})
            S.append(f"| {r} | {nm} | {st} | " + " | ".join(c) +
                     f" | {bn.get('max_abs_beta', float('nan')):.3f} | {bn.get('max_gamma', float('nan')):.3f} |")
    out = os.path.join(os.path.dirname(OUT), "gradflow_pre.md")
    open(out, "w").write("\n".join(L + S) + "\n")
    print(f"-> {out}")


def gain(root, runs):
    """-> gradflow_gain.md: snapshots at step 50 and at the last record of epochs 1/10/30 (single records, no means)."""
    eps = (1, 10, 30)
    L = ["# Binary-activation STE gain runs (measured)", "",
         f"Source: {root}/<run>/metrics.json, gradflow.jsonl (records every 50 steps, 351 steps/epoch). Snapshot "
         "'s50' = the step-50 record; 'epE' = the last record of epoch E (1-based). g_out = ||dL/db|| per BinAct in "
         "network order (blocks.0.b1, blocks.0.b2, ..., blocks.7.b2). pass / const / t_std / eff = mean over the 16 "
         "BinAct layers; eff = mean over channels of the effective db/du scale (clip: K x frac(|x-t|<w); "
         "bussgang / stein: a_c). b1/b2 = mean over blocks k of g_out(blocks.k.b1) / g_out(blocks.k.b2). "
         "BN: max |beta|, max gamma over all BatchNorm2d at that record. Val = 5k held-out split.", "",
         "| run | best val | best ep | " + " | ".join(f"train ep{e}" for e in eps) + " | b1/b2 s50 |",
         "|---|---|---|" + "---|" * len(eps) + "---|"]
    snaps = {}
    for r in runs:
        m, pick, by = snapshots(os.path.join(root, r), eps)
        order = sorted((k for k in by[50] if k != "bn" and by[50][k]["kind"] == "binact"),
                       key=lambda s: (int(s.split(".")[1]), s))
        rt = [by[50][f"blocks.{k}.b1"]["g_out"] / by[50][f"blocks.{k}.b2"]["g_out"] for k in range(8)]
        snaps[r] = (pick, by, order)
        h = m["history"]
        L.append(f"| {r} | {100 * m['best_val']:.2f} | {m['best_epoch'] + 1} | "
                 + " | ".join(f"{100 * h[e - 1]['train_acc']:.2f}" if e <= len(h) else "-" for e in eps)
                 + f" | {sum(rt) / len(rt):.3f} |")
    for r, (pick, by, order) in snaps.items():
        L += ["", f"## {r}", "", "| snap | step | g_out (16 BinActs) | pass | const | t_std | eff | BN max abs beta | BN max gamma |",
              "|---|---|---|---|---|---|---|---|---|"]
        for nm, st in pick:
            if st is None:
                L.append(f"| {nm} | - |" + " - |" * 7)
                continue
            d = by[st]
            av = lambda f: sum(d[k][f] for k in order) / len(order)
            bn = d.get("bn", {})
            L.append(f"| {nm} | {st} | " + " ".join(f"{d[k]['g_out']:.3g}" for k in order) +
                     f" | {av('pass'):.3f} | {av('const'):.3f} | {av('t_std'):.3f} | {av('eff'):.4g} | "
                     f"{bn.get('max_abs_beta', float('nan')):.3f} | {bn.get('max_gamma', float('nan')):.3f} |")
    out = os.path.join(os.path.dirname(OUT), "gradflow_gain.md")
    open(out, "w").write("\n".join(L) + "\n")
    print(f"-> {out}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=f"/tmp/{getpass.getuser()}/qc18b/pilot")
    ap.add_argument("--runs", default="fp60,bin_scratch,bin_init,bin_scratch_approx")
    ap.add_argument("--gain", type=int, default=0, help="1: gradflow_gain.md (snapshot tables) instead")
    ap.add_argument("--pre", type=int, default=0, help="1: gradflow_pre.md (pre-ReLU b1 runs) instead")
    a = ap.parse_args()
    if a.pre:
        return pre(a.root, [r for r in a.runs.split(",") if os.path.exists(os.path.join(a.root, r, "metrics.json"))])
    if a.gain:
        return gain(a.root, [r for r in a.runs.split(",") if os.path.exists(os.path.join(a.root, r, "metrics.json"))])
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
