"""fidelity2.py JSON -> markdown tables.   python3 -m qc18b.diag.fidelity2_table JSON > MD"""
import statistics
import sys
import json

from qc18b.diag.fidelity import stats

r = json.load(open(sys.argv[1]))
G, K, P, A = r["groups"], r["kinds"], r["proj"], r["actual"]
EPS = list(A["A"][G[0]].keys())
corr = lambda a, b: stats(a, b)[0]
f = lambda v: f"{v:.2f}"


def table(cols, fn):
    """cols: [(header, key)], fn(group, key) -> float.  rows = groups + median over bn / t groups."""
    out = ["| group | " + " | ".join(h for h, _ in cols) + " |", "|---" * (len(cols) + 1) + "|"]
    vals = {g: [fn(g, k) for _, k in cols] for g in G}
    for g in G:
        out.append(f"| {g} | " + " | ".join(f(v) for v in vals[g]) + " |")
    for kind in ("bn", "t"):
        gs = [g for g in G if K[g] == kind]
        out.append(f"| **median {kind}** | " + " | ".join(f(statistics.median(vals[g][i] for g in gs)) for i in range(len(cols))) + " |")
    return "\n".join(out)


wc = [k[6:] for k in P if k.startswith("C_clip") and "check" not in k and "_K" not in k]
wt = [k[5:] for k in P if k.startswith("C_tri") and "_K" not in k]
ks = sorted({k.split("_K")[1] for k in P if "_K" in k})
print(f"""# STE fidelity part 2: target reliability, batch size, STE window sweep (qc18b, CIFAR-100, binary, measurement only)

Produced by `qc18b/diag/fidelity2.py` + `fidelity2_table.py` (raw: `results/fid2/PK60_k.json` = `PK60.json` + K=0.6 sweep from `--sweep-only`, log `PK60.log`). Checkpoint `{r['ckpt']}` (binact opts {r['binact_opts']}).
Groups: BN (gamma, beta) of c1 / c2 and BinAct t of b1 / b2, blocks 0, 2, 4, 6. N = {r['n']} Gaussian directions per group (||d|| = 1, drawn once, the same for every batch / eps / STE); delta = eps ||p_G|| d; pred = eps ||p_G|| <g_G, d>; actual = (L(p+delta) - L(p-delta)) / 2; corr = Pearson over the N directions. Train mode (BN batch stats over the whole batch), fp32, TF32 off, eager, mean CE, no aug, train split only.
Batches: A = randperm(45000, seed 0)[:512] (the fidelity.md batch), B = first 512 of randperm(seed 1) not in A (disjoint from A), C = randperm(seed 2)[:{r['bsC']}] (may overlap A / B), one forward / backward over all of C ({r['bsC']}, fits: peak 33.4 GB). L(p): A {r['L0']['A']:.4f}, B {r['L0']['B']:.4f}, C {r['L0']['C']:.4f}.
Directions differ from fidelity.md (only 16 groups drawn here), so A numbers are not identical to that file.

## 1. Reliability of the target (A vs B, 512 each) and pred-vs-actual on A, B, C (trained STE: clip w=1, K=0.6)
""")
cols = [(f"act A~B {e}", ("ab", e)) for e in EPS] + [("pred A~B", ("pp", None))] + \
       [(f"{b}: pred~act {e}", (b, e)) for b in "ABC" for e in EPS]


def fn1(g, k):
    if k[0] == "ab":
        return corr(A["A"][g][k[1]], A["B"][g][k[1]])
    if k[0] == "pp":
        return corr(P["A"][g], P["B"][g])
    return corr(P[k[0]][g], A[k[0]][g][k[1]])


print(table(cols, fn1))
print("\npred A~B is eps-independent (pred is eps ||p|| <g, d>).\n")
print("## 2. STE window sweep on batch C: corr(pred_w, actual_C) (gradient only; forward unchanged)\n")
print("clip: db/du = K 1[|u| < w]; tri: db/du = K (1 - |u|/w)+, applied in every BinAct. **K is not a global constant**: "
      "the residual path (relu(s)) and the BN/fc paths carry no K, so a per-BinAct K reweights paths through 0..16 BinActs. "
      "Measured: corr(pred_C trained STE, pred_C sweep clip w=1 K=1) min over groups = "
      f"{min(corr(P['C'][g], P['C_clip1_check'][g]) for g in G):.3f}; with K=0.6: "
      + (f"{min(corr(P['C'][g], P['C_clip1_check_K' + ks[0]][g]) for g in G):.6f}" if ks else "-") +
      ". The sweep is therefore reported at K = 1 (as specified) and at K = 0.6 (the trained K; clip 1 K=0.6 = the trained STE exactly).\n")
for kk in [""] + [f"_K{k}" for k in ks]:
    for e in EPS:
        print(f"### K = {kk[2:] or '1'}, eps = {e}\n")
        print(table([(f"clip {w}", f"C_clip{w}{kk}") for w in wc] + [(f"tri {w}", f"C_tri{w}{kk}") for w in wt],
                    lambda g, k: corr(P[k][g], A["C"][g][e])))
        print()
print("## 3. Fraction of BinAct input elements with |u| < w on batch C (u = x - t_c, all 16 BinActs)\n")
fr = r["frac"]
ws = list(next(iter(fr.values())).keys())
print("| BinAct | " + " | ".join(f"w={w}" for w in ws) + " |\n" + "|---" * (len(ws) + 1) + "|")
for nm, v in fr.items():
    print(f"| {nm} | " + " | ".join(f"{v[w]:.3f}" for w in ws) + " |")
print("| **median** | " + " | ".join(f"{statistics.median(v[w] for v in fr.values()):.3f}" for w in ws) + " |")
