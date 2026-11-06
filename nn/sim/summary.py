#!/usr/bin/env python3
"""Summarise RTL run directories of nn/sim/run_rtl.sh (build/nn_rtl/<tag>/).

    summary.py <run dir> [<run dir> ...]

Inputs per run: result.json (nn_result decoded from the memory island), gen/nn_net.c (expected
logits), compile.txt (labels, GeMMX fires per conv), run.log (JTAG exit code).  Prints per image:
bit-exact or not, prediction vs label, cycles; then over all images of all runs: the per-step
cycles (mean), the breakdown by kind and the GeMMX counters / utilisation (counters of each run's
first image).  Exit 0 iff every run finished and every checksum and logit matched.
"""
import json
import re
import sys
from pathlib import Path

KINDS = ["GeMMX conv", "residual add", "pool+FC", "input DMA"]


def kind(n):
    return ("GeMMX conv" if n.startswith("conv") else "residual add" if n.startswith("add")
            else "pool+FC" if n == "poolfc" else "input DMA")


def ints(s):
    return [int(v) for v in re.findall(r"-?\d+", re.sub(r"np\.int64", "", s))]


def load(d):
    """One run -> (ok, step names, fires per conv, list of per-image dicts, gemmx/streamer counters)."""
    r = json.loads((d / "result.json").read_text())
    net = (d / "gen/nn_net.c").read_text()
    comp = (d / "compile.txt").read_text()
    log = (d / "run.log").read_text(errors="replace")
    names = re.search(r"nn_step_names\[NN_N_STEPS\] = \{(.*?)\};", net).group(1).replace('"', "").split(", ")
    blk = net[net.index("nn_expect_logits"):]
    exp = [ints(row) for row in re.findall(r"\{([-\d, ]+)\}", blk[:blk.index("};")])]
    m = re.search(r"images \[([^\]]*)\], labels \[([^\]]*)\]", comp)
    idx, labels = ints(m.group(1)), ints(m.group(2))
    fires = {n: int(f) for n, f in re.findall(r"^\s+(conv\d)\s+\d+\s+GeMMX .*fires=(\d+)", comp, re.M)}
    code = re.search(r"\[JTAG\] (SUCCESS|FAILED.*)", log)
    end = re.search(r"NN_SIM_END (\d+)", log)
    ok = r["marker"] == 0xC0FFEE00 and r["errors"] == 0
    print(f"run {d.name}: JTAG {code.group(1) if code else 'no exit code'}, marker 0x{r['marker']:08x}, "
          f"errors {r['errors']}, sim end {int(end.group(1)) / 1e9 if end else -1:.3f} ms")
    if r["first_bad"] != 0xFFFFFFFF and r["marker"] == 0xC0FFEE00:
        print(f"  first mismatch: image {idx[r['first_bad'] >> 8]} step {names[r['first_bad'] & 0xFF]}")
    if any(r["full_err"]):
        f = r["full_first"]
        print("  NN_FULL_CHECK bad bytes/step: " + ", ".join(f"{n} {e}" for n, e in zip(names, r["full_err"]) if e))
        print(f"  first bad byte: step {names[f[0] >> 24]} index {f[0] & 0xFFFFFF} got {f[1]} expected {f[2]}")
    elif r["marker"] == 0xC0FFEE00 and "NN_FULL_CHECK" in (d / "cmd.txt").read_text():
        print("  NN_FULL_CHECK: every byte of every step output of the first image matches")
    imgs = []
    for k, (i, lab) in enumerate(zip(idx, labels)):
        if r["total"][k] == 0:
            print(f"  image {i}: not run")
            ok = False
            continue
        same = r["logits"][k] == exp[k]
        ok &= same
        imgs.append(dict(idx=i, label=lab, pred=r["pred"][k], exact=same, total=r["total"][k], cycles=r["cycles"][k]))
        print(f"  image {i:5d}: logits {'BIT-EXACT' if same else 'MISMATCH'}  pred {r['pred'][k]} label {lab}  "
              f"cycles {r['total'][k]}")
    return ok, names, fires, imgs, r["gemmx_perf"], r["streamer_perf"]


def main(dirs):
    runs = [load(Path(d)) for d in dirs]
    ok = all(r[0] for r in runs)
    names, fires = runs[0][1], runs[0][2]
    imgs = [i for r in runs for i in r[3]]
    if not imgs:
        return 1
    n = len(imgs)
    steps = [sum(i["cycles"][s] for i in imgs) / n for s in range(len(names))]
    tot = sum(steps)
    exact = sum(i["exact"] for i in imgs)
    correct = sum(i["pred"] == i["label"] for i in imgs)
    tots = [i["total"] for i in imgs]
    print(f"\n{n} images: {exact} bit-exact, {correct} correctly classified; cycles/image mean {tot:.0f} "
          f"(min {min(tots)}, max {max(tots)})")
    for k in KINDS:
        v = sum(s for nm, s in zip(names, steps) if kind(nm) == k)
        print(f"  {k:13s} {v:9.0f}  {100 * v / tot:5.1f} %")
    print("\nstep      cycles   gemm_busy  streamer  fires  fires/busy")
    gsum = fsum = 0
    for s, nm in enumerate(names):
        g = sum(r[4][s] for r in runs) / len(runs)
        st = sum(r[5][s] for r in runs) / len(runs)
        extra = ""
        if nm in fires:
            gsum += g
            fsum += fires[nm]
            extra = f"{g:9.0f} {st:9.0f} {fires[nm]:6d}  {100 * fires[nm] / g if g else 0:5.1f} %"
        print(f"  {nm:7s} {steps[s]:8.0f} {extra}")
    if gsum:
        print(f"  GeMMX: busy {gsum:.0f} cycles for {fsum} fires = {100 * fsum / gsum:.1f} % array utilisation "
              f"while busy; busy {100 * gsum / tot:.1f} % of the image; fires / image cycles {100 * fsum / tot:.1f} %")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
