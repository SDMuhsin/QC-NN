"""actmeas JSON -> markdown tables:  python3 -m qc18b.diag.actmeas_table S8KD.json [S8.json ...] > OUT.md"""
import json
import sys


def fmt(v, p=4):
    return f"{v:.{p}g}"


def main():
    rs = [json.load(open(p)) for p in sys.argv[1:]]
    r = rs[0]
    names = r["names"]
    print(f"# qc18b actmeas (measured; CIFAR-100 val 5k split; fp32 eval)\n")
    print("Produced by `python3 -m qc18b.diag.actmeas` (definitions in its docstring) and `qc18b.diag.actmeas_table`.\n")
    for x in rs:
        print(f"- {x['tag']}: `{x['ckpt']}`, val acc (unmodified, eval) {100 * x['val_acc']:.2f} %")
    if "m1" in r and r["m1"]:
        print(f"\n## M1 conv-input statistics ({r['tag']}, val 5k)\n")
        print("| conv | input C×H×W | frac 0 | p50 | p90 | p99 | max | ch-mean min/med/max | ch-zero-frac min/med/max |")
        print("|---|---|---|---|---|---|---|---|---|")
        for n, s, m in zip(names, r["shape"], r["m1"]):
            print(f"| {n} | {'×'.join(map(str, s))} | {m['zero']:.4f} | {fmt(m['p50'])} | {fmt(m['p90'])} | "
                  f"{fmt(m['p99'])} | {fmt(m['max'])} | {' / '.join(fmt(v, 3) for v in m['cmean'])} | "
                  f"{' / '.join(f'{v:.3f}' for v in m['czero'])} |")
    if "m2" in r and r["m2"]:
        print(f"\n## M2 single-conv input binarisation, conv output (pre-BN) error ({r['tag']}, val 5k)\n")
        print("rel = ‖conv(x_b)−conv(x)‖/‖conv(x)‖; cos = cosine; relc = rel after subtracting per-output-channel "
              "means (over N,H,W) from both outputs; relin = ‖x_b−x‖/‖x‖ (input).\n")
        print("| conv | (i) rel | (i) cos | (i) relc | (ii) rel | (ii) cos | (ii) relc | (iii) rel | (iii) cos | "
              "(iii) relc | relin (i)/(ii)/(iii) |")
        print("|---|---|---|---|---|---|---|---|---|---|---|")
        for n, m in zip(names, r["m2"]):
            row = " | ".join(f"{m[v]['rel']:.3f} | {m[v]['cos']:.4f} | {m[v]['relc']:.3f}" for v in ("i", "ii", "iii"))
            rin = " / ".join(f"{m[v]['relin']:.3f}" for v in ("i", "ii", "iii"))
            print(f"| {n} | {row} | {rin} |")
    m3s = [x for x in rs if "m3" in x]
    if m3s:
        print("\n## M3 post-hoc val accuracy, variant (iii) binarised inputs, BN recal on train[:10000]\n")
        print("Thresholds/scale fitted on train[:10000] of the unmodified net ('seq': conv i fitted on the net with "
              "convs < i binarised + BN recal).  drop = unmodified val acc − acc (pp).\n")
        print("| | " + " | ".join(x["tag"] for x in m3s) + " |")
        print("|---|" + "---|" * len(m3s))
        print("| unmodified | " + " | ".join(f"{100 * x['m3']['base']:.2f}" for x in m3s) + " |")
        print("| BN recal only | " + " | ".join(f"{100 * x['m3']['recal_only']:.2f}" for x in m3s) + " |")
        for k, lab in (("b", "(b) 19 non-stem"), ("c", "(c) all 20"), ("b_seq", "(b) 19 non-stem, seq refit"),
                       ("c_seq", "(c) all 20, seq refit")):
            print(f"| {lab} | " + " | ".join(f"{100 * x['m3'][k]:.2f}" for x in m3s) + " |")
        print("\n(a) one conv at a time: acc % (drop pp)\n")
        print("| conv | " + " | ".join(x["tag"] for x in m3s) + " |")
        print("|---|" + "---|" * len(m3s))
        for i, n in enumerate(names):
            print(f"| {n} | " + " | ".join(f"{100 * x['m3']['a'][i]:.2f} ({100 * (x['m3']['base'] - x['m3']['a'][i]):+.2f})"
                                           for x in m3s) + " |")
    if "m4" in r:
        print(f"\n## M4 gradient at conv inputs ({r['tag']}, BN train mode, train[:500], CE loss "
              f"{r['m4_loss']:.4f})\n")
        print("g = dL/dx through that conv only; win = frac of x with |x − t_c| < std_c ((ii) thresholds from val, "
              "std_c per channel on the batch).\n")
        print("| conv | ‖g‖ | ‖g‖/‖x‖ | win |")
        print("|---|---|---|---|")
        for n, m in zip(names, r["m4"]):
            print(f"| {n} | {m['g']:.4g} | {m['gx']:.4g} | {m['win']:.4f} |")


if __name__ == "__main__":
    main()
