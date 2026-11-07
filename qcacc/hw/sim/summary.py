"""Summary of s2 chimera RTL runs (qcacc/hw/sim/run_rtl_qc.sh), also of -DNN_STOP_AFTER runs.

    python3 -m qcacc.hw.sim.summary RUN_DIR [RUN_DIR ...] [--qparams S2] [--mode qc|gemmx] [--per-group]

Per run: result.json (nn_result from the memory island), gen/nn_net.c (step names, expected logits),
cmd.txt (first image), run.log.  Prints per image: bit-exact or not, prediction vs label, cycles; then
over all images of all runs: mean cycles per step, the breakdown GeMMX convs / residual adds / pool+FC /
input DMA, and per conv the GeMMX / streamer busy counters (first image of each run, averaged) vs the
array fires (K*M*N of its calls).  Exit 0 iff every run finished (or reached its NN_STOP_AFTER marker)
with 0 checksum / NN_FULL_CHECK errors and every logit bit-exact.
"""
import argparse
import json
import re
from pathlib import Path

S2 = "/tmp/root/qc/final/int8/s2.pt"
KINDS = ["GeMMX conv", "residual add", "pool+FC", "input DMA"]


def kind(n):
    return ("GeMMX conv" if n.startswith("conv") else "residual add" if n.startswith("add")
            else "pool+FC" if n == "poolfc" else "input DMA")


def load(d, labels_all):
    r = json.loads((d / "result.json").read_text())
    net = (d / "gen/nn_net.c").read_text()
    names = re.search(r"nn_step_names\[NN_N_STEPS\] = \{(.*?)\};", net).group(1).replace('"', "").split(", ")
    blk = net[net.index("nn_expect_logits"):]
    exp = [[int(v) for v in row.split(",")] for row in re.findall(r"\{([-\d, ]+)\}", blk[:blk.index("};")])]
    cmd = (d / "cmd.txt").read_text()
    first = int(re.search(r"--first (\d+)", cmd).group(1))
    log = (d / "run.log").read_text(errors="replace")
    end = re.search(r"NN_SIM_END (\d+)", log)
    marker = r["marker"]
    stop = (marker >> 16) == 0xDEAD
    full = marker == 0xC0FFEE00
    ok = r["errors"] == 0 and (stop or full) and not any(r["full_err"])
    print(f"run {d.name}: marker 0x{marker:08x} ({'stopped after ' + names[marker & 0xFFFF] if stop else 'complete' if full else 'NOT FINISHED'}), "
          f"errors {r['errors']}, sim end {int(end.group(1)) / 1e9 if end else -1:.3f} ms")
    if r["first_bad"] != 0xFFFFFFFF:
        print(f"  first mismatch: image {first + (r['first_bad'] >> 8)} step {names[r['first_bad'] & 0xFF]}")
    if "NN_FULL_CHECK" in cmd:
        print(f"  NN_FULL_CHECK (image {first}): {sum(r['full_err'])} bad bytes"
              + ("" if not any(r["full_err"]) else ": " + ", ".join(f"{n} {e}" for n, e in zip(names, r["full_err"]) if e)))
    imgs = []
    last = (marker & 0xFFFF) if stop else len(names) - 1
    for k in range(len(exp)):
        i = first + k
        if r["total"][k] == 0 and not (stop and k == 0):
            print(f"  image {i}: not run")
            ok &= stop
            continue
        same = full and r["logits"][k] == exp[k]
        ok &= same or stop
        imgs.append(dict(idx=i, label=labels_all[i], pred=r["pred"][k], exact=same, total=r["total"][k],
                         cycles=r["cycles"][k]))
        if full:
            print(f"  image {i:5d}: logits {'BIT-EXACT' if same else 'MISMATCH'}  pred {r['pred'][k]} "
                  f"label {labels_all[i]}  cycles {r['total'][k]}")
    return ok, names, imgs, r["gemmx_perf"], r["streamer_perf"], last, full


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--qparams", default=S2)
    ap.add_argument("--mode", default="qc")
    ap.add_argument("--per-group", action="store_true")
    a = ap.parse_args()

    import torch
    from nn.model.data import test_set
    from qcacc.compile.lower import QCProgram
    _, yt = test_set()
    prog = QCProgram(torch.load(a.qparams, weights_only=False), a.mode, True if a.per_group else None)
    fires = {st.name: st.cfg["K"] * st.cfg["M"] * st.cfg["N"] for st in prog.steps if st.kind == "conv"}

    runs = [load(Path(d), [int(y) for y in yt]) for d in a.runs]
    ok = all(r[0] for r in runs)
    names, last = runs[0][1], runs[0][5]
    imgs = [i for r in runs for i in r[2]]
    n = len(imgs)
    steps = [sum(i["cycles"][s] for i in imgs) / n for s in range(last + 1)]
    tot = sum(steps)
    if all(r[6] for r in runs):
        exact = sum(i["exact"] for i in imgs)
        correct = sum(i["pred"] == i["label"] for i in imgs)
        tots = [i["total"] for i in imgs]
        print(f"\n{n} images: {exact} bit-exact, {correct} correctly classified; cycles/image mean {tot:.0f} "
              f"(min {min(tots)}, max {max(tots)})")
    else:
        print(f"\n{n} image(s), steps up to {names[last]}: {tot:.0f} cycles")
    for k in KINDS:
        v = sum(s for nm, s in zip(names, steps) if kind(nm) == k)
        print(f"  {k:13s} {v:9.0f}  {100 * v / tot:5.1f} %")
    print("\nstep        cycles  gemm_busy  streamer   fires  fires/busy   (counters: first image of each run)")
    per, gsum, fsum = {}, 0, 0
    for s in range(last + 1):
        nm = names[s]
        g = sum(r[3][s] for r in runs) / len(runs)
        st = sum(r[4][s] for r in runs) / len(runs)
        line = f"  {nm:10s} {steps[s]:7.0f}"
        if nm in fires:
            line += f"  {g:9.0f} {st:9.0f} {fires[nm]:7d}  {100 * fires[nm] / g if g else 0:5.1f} %"
            p = per.setdefault(nm.split("_g")[0], [0, 0, 0, 0, 0])
            for j, v in enumerate((steps[s], g, st, fires[nm], 1)):
                p[j] += v
            gsum += g
            fsum += fires[nm]
        print(line)
    if any(p[4] > 1 for p in per.values()):
        print("per conv (sum of its group calls):  cycles  gemm_busy  streamer  fires")
        for nm, (c, g, st, f, _) in per.items():
            print(f"  {nm:6s} {c:8.0f} {g:9.0f} {st:9.0f} {f:6d}")
    if gsum:
        print(f"  GeMMX: {sum(p[4] for p in per.values())} calls, busy {gsum:.0f} cycles for {fsum} fires = "
              f"{100 * fsum / gsum:.1f} % array utilisation while busy; conv steps {sum(p[0] for p in per.values()):.0f} cycles")
    print("RESULT:", "BIT-EXACT" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
