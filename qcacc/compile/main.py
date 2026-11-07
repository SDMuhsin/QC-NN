"""Compile s2 for the KUL cluster in one mode and check the schedule on the host.

    python3 -m qcacc.compile.main --mode gemmx|qc [--per-group] [--qparams S2] [--check N] [--images N]
                                  [--first I] [--out DIR] [--acc]
  1. lowers the int8 qparams (qcacc.compile.lower.QCProgram): qc mode one GeMMX call per conv with the
     per-channel requant table (--per-group: one call per 8-channel group, as gemmx mode always does)
  2. runs the schedule model (nn.compile.schedule_sim.run_image; qc mode with the QC array model)
     on --check test images and compares every step output (every group) and the logits with
     nn.quant.quantize.IntResNet8, bit for bit; prints the QC select activity per conv
  3. emits DIR/nn_net.{h,c}, nn_full.c (nn.compile.emit) for --images test images
  4. prints GeMMX calls, weight bytes, the cycle estimate and the dense baseline's (nn/build/qparams.pt)
  --acc: int8 accuracy of IntResNet8 on the 10k test set
"""
import argparse
import os
from types import SimpleNamespace

import numpy as np
import torch

from nn.compile.emit import emit
from nn.compile.lower import Program
from nn.compile.main import ref_run
from nn.compile.schedule_sim import cycle_estimate, run_image
from nn.model.data import test_set
from nn.model.resnet8 import evaluate
from nn.quant.quantize import BUILD, IntResNet8

from ..model.array import SEL_NAMES
from .lower import MODES, QCProgram
from .sim import make_gemm

QCACC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S2 = "/tmp/root/qc/final/int8/s2.pt"


def taps_for(prog, im, x):
    """Reference taps (C8HW8 interiors) of the real tensors + the one-group views."""
    real = {n: t for n, t in prog.tensors.items() if "_g" not in n}
    taps, logits = ref_run(im, SimpleNamespace(tensors=real), x)
    for d in taps:
        for n in prog.tensors:
            if "_g" in n:
                p, g = n.split("_g")
                d[n] = d[p][int(g):int(g) + 1]
    return taps, logits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=MODES, required=True)
    ap.add_argument("--qparams", default=S2)
    ap.add_argument("--baseline", default=os.path.join(BUILD, "qparams.pt"), help="dense qparams (cycle comparison)")
    ap.add_argument("--check", type=int, default=1000)
    ap.add_argument("--images", type=int, default=8)
    ap.add_argument("--first", type=int, default=0)
    ap.add_argument("--out")
    ap.add_argument("--acc", action="store_true")
    ap.add_argument("--per-group", action="store_true", help="qc mode: one call per 8-channel group (42 calls)")
    a = ap.parse_args()
    out = a.out or os.path.join(QCACC, "build", a.mode, "gen")

    q = torch.load(a.qparams, weights_only=False)
    im = IntResNet8(q)
    xt, yt = test_set()
    if a.acc:
        print(f"int8 accuracy (IntResNet8, {a.qparams}, 10k test): {100 * evaluate(im.forward, xt, yt):.2f} %")
    prog = QCProgram(q, a.mode, True if a.per_group else None)

    # --- schedule model vs integer reference -------------------------------------------
    stats = {}
    gemm = make_gemm(a.mode, prog, stats)
    mem = np.random.default_rng(1).integers(0, 256, 128 * 1024, dtype=np.uint8)
    n_chk = max(a.check, a.images)
    bad = agree = 0
    first_taps = first_logits = None
    for c0 in range(a.first, a.first + n_chk, 250):
        idx = list(range(c0, min(c0 + 250, a.first + n_chk)))
        taps, logits = taps_for(prog, im, xt[idx])
        if first_taps is None:
            first_taps, first_logits = taps[:a.images], logits[:a.images]
        for j, i in enumerate(idx):
            def check(st, m, j=j, i=i):
                nonlocal bad
                if st.out and not np.array_equal(prog.tensors[st.out].interior(m), taps[j][st.out]):
                    bad += 1
                    print(f"MISMATCH image {i} step {st.out}")
            lg = run_image(prog, mem, prog.input_image(taps[j]["_input_nchw"]), check, gemm)
            if not np.array_equal(lg, logits[j]):
                bad += 1
                print(f"MISMATCH image {i} logits")
            agree += int(np.argmax(lg) == yt[i])
    n_out = sum(1 for st in prog.steps if st.out)
    print(f"[{a.mode}] schedule model vs IntResNet8: {n_chk} images x ({n_out} step outputs + logits), "
          f"{bad} mismatches ({'BIT-EXACT' if bad == 0 else 'FAIL'}); accuracy on them {100 * agree / n_chk:.1f} %")
    if stats:
        print("QC array select activity per image (muxes = fires x 8 rows x 8 cols x 4 pairs):")
        tot = {}
        for n, s in stats.items():
            for k in ("fires", "selects", "nz_code", "nz_data"):
                tot[k] = tot.get(k, 0) + s[k] // n_chk
            kinds = " ".join(f"{SEL_NAMES[i]} {s['by_kind'][i] / s['selects']:.1%}" for i in range(1, 5))
            print(f"  {n:6s} muxes {s['selects'] // n_chk:8d}  nonzero code {s['nz_code'] / s['selects']:.1%}  "
                  f"nonzero value {s['nz_data'] / s['selects']:.1%}  ({kinds})")
        print(f"  total  muxes {tot['selects']:8d}  nonzero code {tot['nz_code'] / tot['selects']:.1%}  "
              f"nonzero value {tot['nz_data'] / tot['selects']:.1%}")

    # --- emit C ----------------------------------------------------------------------------
    images = [prog.input_image(t["_input_nchw"]) for t in first_taps]
    sizes = emit(prog, images, first_taps, first_logits, out)
    print(f"wrote {out}/nn_net.[ch], nn_full.c: {a.images} images from {a.first}, {len(prog.steps)} steps, "
          f"TCDM peak {prog.peak} B of {prog.arena}, blobs {sizes['blob_bytes']} B")

    # --- calls, bytes, cycles ----------------------------------------------------------------
    useful, fires = prog.macs()
    tiles = sum(st.cfg["K"] * st.cfg["N"] for st in prog.steps if st.kind == "conv")
    raw = tiles * (8 if a.mode == "qc" else 64)
    print(f"GeMMX calls/image {prog.calls()}, fires {fires}, useful MACs {useful}; B tiles {tiles} = {raw} B "
          f"({prog.weight_bytes()} B 64B-padded), conv blobs incl. bias tiles + nn_conv_t "
          f"{sum(b.size for b in prog.blobs if b.name.startswith('w_conv'))} B")
    rows = cycle_estimate(prog)
    tot = sum(r[1] for r in rows)
    g = sum(r[1] for r, s in zip(rows, prog.steps) if s.kind == "conv")
    base = Program(torch.load(a.baseline, weights_only=False))
    brows = cycle_estimate(base)
    btot = sum(r[1] for r in brows)
    bg = sum(r[1] for r, s in zip(brows, base.steps) if s.kind == "conv")
    print(f"cycle model / image: {tot} (GeMMX steps {g}, cores {tot - g});  dense baseline {btot} "
          f"(GeMMX {bg}, 9 calls; RTL measured 401.7 k)  -> {tot / btot:.3f}x")


if __name__ == "__main__":
    main()
