"""Merge qc18b.diag.fidelity JSONs -> markdown tables (binary and FP side by side).

    python3 -m qc18b.diag.fidelity_table --bin 'DIR/PK60_*.json' --fp 'DIR/F30_*.json' --out FILE.md
"""
import argparse
import glob
import json
import statistics

EPS = (1e-3, 1e-2, 3e-2, 1e-1)


def load(pat):
    groups, full, meta = {}, None, {}
    for f in sorted(glob.glob(pat)):
        for ck, r in json.load(open(f)).items():
            meta = dict(ckpt=ck, L0=r["L0"], L0_repeat=r["L0_repeat"], opts=r["binact_opts"])
            for g in r["groups"]:
                groups[g["name"]] = g
            if "full" in r:
                full = r["full"]
    return groups, full, meta


def order(name):
    if name.startswith("stem"):
        return (-1, name)
    if name == "fc":
        return (99, name)
    return (int(name.split(".")[0][1:]), name)


def row(g, eps):
    return next(q for q in g["rows"] if q["eps"] == eps)


def f(v, d=2):
    return "nan" if v != v else f"{v:.{d}f}"


def spread(vals):
    vals = [v for v in vals if v == v]
    if not vals:
        return "-"
    return f"{min(vals):.2f} / {statistics.median(vals):.2f} / {max(vals):.2f}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--fp", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    B, Bf, Bm = load(a.bin)
    F, Ff, Fm = load(a.fp)
    n = None
    L = ["# STE fidelity: predicted vs actual loss change (qc18b, CIFAR-100, measurement only)", ""]
    L.append("Produced by `qc18b/diag/fidelity.py` + `fidelity_table.py`. Checkpoints (epoch 30, last.pt): "
             f"binary `{Bm['ckpt']}` (binact opts {Bm['opts']}), FP `{Fm['ckpt']}` (opts {Fm['opts']}).")
    L.append("Batch: 512 train-split images (randperm seed 0, no aug); train mode (BN batch stats); fp32, TF32 off, "
             "eager; loss = mean CE. "
             f"L(p): binary {Bm['L0']:.6f} (repeat {Bm['L0_repeat']:.6f}), FP {Fm['L0']:.6f} (repeat {Fm['L0_repeat']:.6f}).")
    L.append("Per group: N random Gaussian directions on the group, ||d|| = 1, delta = eps ||p_G|| d; "
             "pred = eps ||p_G|| <g_G, d> (g = autograd grad incl. the model's STEs), "
             "actual = (L(p+delta) - L(p-delta)) / 2. corr = Pearson over the N directions, slope = OLS slope actual ~ pred. "
             "N = 32 (not 64: time box). Shortcut (sc) groups and stem theta not measured.")
    L.append("")
    L.append("## Summary: min / median / max over layers")
    L.append("")
    L.append("| kind | eps | binary corr | binary slope | FP corr | FP slope |")
    L.append("|---|---|---|---|---|---|")
    for kind in ("bn", "t", "theta", "fc"):
        for eps in EPS:
            cells = []
            for G in (B, F):
                gs = [g for g in G.values() if g["kind"] == kind]
                cells += [spread([row(g, eps)["corr"] for g in gs]), spread([row(g, eps)["slope"] for g in gs])]
            L.append(f"| {kind} | {eps:g} | " + " | ".join(cells) + " |")
    L.append("")
    L.append("bn includes stem.bn (16 + 1 groups per model); fc = fc weight + bias.")
    L.append("")
    for kind, title in (("bn", "BN groups (gamma, beta)"), ("t", "BinAct thresholds t (binary only)"),
                        ("theta", "theta (through the weight-projection STE)"), ("fc", "fc")):
        names = sorted({k for G in (B, F) for k, g in G.items() if g["kind"] == kind}, key=order)
        L.append(f"## {title}: corr / slope")
        L.append("")
        hdr = "| group | " + " | ".join(f"bin {e:g}" for e in EPS) + " | " + " | ".join(f"FP {e:g}" for e in EPS) + " |"
        L.append(hdr)
        L.append("|---" * (1 + 2 * len(EPS)) + "|")
        for nm in names:
            cells = []
            for G in (B, F):
                for e in EPS:
                    if nm not in G:
                        cells.append("-")
                        continue
                    q = row(G[nm], e)
                    c = f"{f(q['corr'])} / {f(q['slope'])}"
                    if kind == "theta":
                        c += f" (v {q['frac_v_changed']:.2f}, {q['mean_n_v_changed']:.0f})"
                    cells.append(c)
            L.append(f"| {nm} | " + " | ".join(cells) + " |")
        L.append("")
        if kind == "theta":
            L.append("(v x, n): x = fraction of directions where hard(theta +- delta) differs from hard(theta) in any "
                     "coefficient; n = mean number of changed coefficients per perturbation (mean over the two signs).")
            L.append("")
    L.append("## Full network, d = -g (all non-theta params: BN, t, fc), delta = eps ||p|| d / ||d||")
    L.append("")
    for tag, full in (("binary", Bf), ("FP", Ff)):
        if full is None:
            continue
        L.append(f"{tag}: {full['n_params']} params, ||p|| {full['p_norm']:.3f}, ||g|| {full['g_norm']:.4g}")
        L.append("")
        L.append("| eps | pred | actual central | actual forward L(p+delta)-L(p) | central/pred |")
        L.append("|---|---|---|---|---|")
        for q in full["rows"]:
            L.append(f"| {q['eps']:g} | {q['pred']:.4g} | {q['central']:.4g} | {q['forward']:.4g} | "
                     f"{q['central'] / q['pred']:.3f} |")
        L.append("")
    open(a.out, "w").write("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
