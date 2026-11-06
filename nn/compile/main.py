"""Compile the quantized ResNet-8 for the KUL cluster and check the schedule on the host.

    python -m nn.compile.main [--images N] [--first I] [--check N]
      1. loads build/qparams.pt (python -m nn.quant.quantize)
      2. lowers it (nn.compile.lower): layouts, 9 GeMMX calls, TCDM plan
      3. runs the schedule model (nn.compile.schedule_sim) on --check test images and compares
         every step's output and the logits with the integer reference, bit for bit
      4. emits build/gen/nn_net.{h,c} (+ nn_full.c) for --images test images starting at --first
      5. prints the TCDM plan, memory-island budget and the cycle estimate
"""
import argparse
import os

import numpy as np
import torch

from ..model.data import test_set
from ..quant.quantize import BUILD, IntResNet8
from .emit import emit
from .lower import Program, to_c8hw8
from .schedule_sim import cycle_estimate, run_image

MEMISL = 256 * 1024
CODE_BUDGET = 24 * 1024          # host + cluster code, tables, rodata (measured ~10-14 KiB)


def ref_run(im, prog, x_u8):
    """Integer reference on a batch -> (per-image dict name -> C8HW8 interior, logits)."""
    taps = {}
    with torch.no_grad():
        logits = im.forward(x_u8, taps).numpy()
    out = []
    for i in range(len(x_u8)):
        d = {}
        for n, t in prog.tensors.items():
            v = taps[n][i].numpy()
            d[n] = to_c8hw8(v, t.C8, t.zp)[:, 1:-1, 1:-1, :]
        d["_input_nchw"] = taps["input"][i].numpy()
        out.append(d)
    return out, logits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--qparams", default=os.path.join(BUILD, "qparams.pt"))
    ap.add_argument("--images", type=int, default=2, help="test images embedded in the C program")
    ap.add_argument("--first", type=int, default=0)
    ap.add_argument("--check", type=int, default=200, help="test images run through the schedule model")
    ap.add_argument("--out", default=os.path.join(BUILD, "gen"))
    a = ap.parse_args()

    q = torch.load(a.qparams, weights_only=False)
    prog = Program(q)
    im = IntResNet8(q)
    xt, yt = test_set()

    # --- schedule model vs integer reference --------------------------------------------
    rng = np.random.default_rng(1)
    mem = rng.integers(0, 256, 128 * 1024, dtype=np.uint8)       # TCDM starts as garbage
    idx = list(range(a.first, a.first + max(a.check, a.images)))
    taps, logits = ref_run(im, prog, xt[idx])
    bad, agree = 0, 0
    for j in range(len(idx)):
        def check(st, m, j=j):
            nonlocal bad
            if st.out and not np.array_equal(prog.tensors[st.out].interior(m), taps[j][st.out]):
                bad += 1
                print(f"MISMATCH image {idx[j]} step {st.name}")
        img = prog.input_image(taps[j]["_input_nchw"])
        lg = run_image(prog, mem, img, check)
        if not np.array_equal(lg, logits[j]):
            bad += 1
            print(f"MISMATCH image {idx[j]} logits")
        agree += int(np.argmax(lg) == yt[idx[j]])
    print(f"schedule model vs integer reference: {len(idx)} images, {bad} mismatches "
          f"({'BIT-EXACT' if bad == 0 else 'FAIL'}); accuracy on them {100 * agree / len(idx):.1f} %")

    # --- emit C ----------------------------------------------------------------------------
    n = a.images
    images = [prog.input_image(taps[j]["_input_nchw"]) for j in range(n)]
    sizes = emit(prog, images, taps[:n], logits[:n], a.out)
    useful, fires = prog.macs()
    print(f"\nwrote {a.out}/nn_net.[ch], nn_full.c  (images {idx[:n]}, labels {list(yt[idx[:n]])}, "
          f"ref pred {list(np.argmax(logits[:n], 1))})")
    print(f"TCDM: arena {prog.arena} B, peak {prog.peak} B")
    for t in sorted(list(prog.tensors.values()) + prog.blobs, key=lambda t: (t.live[0], t.addr)):
        print(f"  0x{t.addr:05x} +{t.size:6d}  {t.name:8s} live {t.live}")
    tot = sizes["blob_bytes"] + sizes["image_bytes"] + CODE_BUDGET
    print(f"memory island: blobs {sizes['blob_bytes']} + images {sizes['image_bytes']} + code/tables "
          f"~{CODE_BUDGET} = {tot} B of {MEMISL}; NN_FULL_CHECK adds {sizes['full_bytes']} B "
          f"({'fits' if tot + sizes['full_bytes'] <= MEMISL else 'does NOT fit'})")
    assert tot <= MEMISL, "memory island overflow: reduce --images"

    # --- cycle estimate --------------------------------------------------------------------
    rows = cycle_estimate(prog)
    print(f"\nGeMMX: {sum(s.kind == 'conv' for s in prog.steps)} calls/image, useful MACs {useful}, "
          f"array fires {fires} (x512 MAC = {fires * 512}, padding util {useful / (fires * 512):.1%})")
    print("cycle estimate per image (cluster clock):")
    for name, cyc, note in rows:
        print(f"  {name:7s} {cyc:8d}  {note}")
    tot_c = sum(r[1] for r in rows)
    g = sum(r[1] for r, s in zip(rows, prog.steps) if s.kind == "conv")
    print(f"  total   {tot_c:8d}  (GeMMX steps {g}, cores {tot_c - g})")


if __name__ == "__main__":
    main()
