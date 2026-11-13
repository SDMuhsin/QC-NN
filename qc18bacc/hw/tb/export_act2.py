#!/usr/bin/env python3
"""Vectors of the R2b bench (hw/tb/tb_qb_act2.sv, qb_act2: two contexts, block 6 from S) for whole images:

    CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_act2.py RUN/best.pt OUTDIR --cache DIR [--images 0 1] [--n 100]

Per image i (val[i], never the test set): OUTDIR/img<i>/
  mem_<pi>.txt, exp_<pi>.txt, passes_act.txt   as export_act.py (binary map lines, expected act-port stream of every
                                               array pass, asserted equal to export_core's qb_core stimulus)
  smem_<pi>.txt   block-6 passes: the S image (256 words x 2048 b, hex, word bit 0 = LSB) of the pass's source in the
                  slice-major layout of compile/layout_s.py (HQ / HQD / Z), zero elsewhere
  flags_<pi>.txt  block-6 passes: 'bank idx nz' of every slice of the source (the writer-side zero flags)
  sched.txt       replay of compile/supply.py config C (two contexts, 512-b map port, b6 from S at 2048 b / cycle) for
                  this image (list scheduler of compile/cycles.py, hazard check on):
                    P cyc ctx pi                 pass command on context ctx at cycle cyc (= model context start - 1)
                    T cyc ctx pi tp ct           tile token (= scheduled array start s of the tile)
                    L pi pos ra seq              load permission of a tile, in commit order: the loader may load its
                                                 rows / S words up to position pos from cycle ra (RAW ready), age seq
                    X pi tp ct ce                model end of the tile (last item issue + 1)
                    F cyc bank pi                producer writes the zero flags of pass pi's source bank from cycle cyc
                                                 (one flag per cycle, done before the pass's first RAW ready)
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402
import torch  # noqa: E402

from qc18bacc.compile import dataflow as D  # noqa: E402
from qc18bacc.compile import layout_s as LS  # noqa: E402
from qc18bacc.compile import program as P  # noqa: E402
from qc18bacc.compile import supply as SU  # noqa: E402
import export_act as EA  # noqa: E402

KIND = {"wc1": ("hq", 0), "wsc": ("hqd", 1), "wc2": ("z", 2)}
CFG_C = dict(width=512, b6="S", ctx=2)


def b6_sources(prog, x, dev):
    """{pi: source buffer entries (one image)} of the block-6 int8 array passes."""
    Ws = {p.name: D.PEWeights(p, dev) for p in prog.passes if p.k}
    bf = D.Bufs(1, dev)
    D.load_image(prog, bf, x, dev)
    out = {}
    with torch.no_grad():
        for pi, p in enumerate(prog.passes):
            if p.k and p.inb == 8 and p.kind != "stem":
                out[pi] = bf.b[p.src][0].cpu().numpy().copy()
            D.do_pass(prog, p, bf, Ws, dev, {})
    return out


def write_s(prog, srcs, outdir):
    for pi, t in srcs.items():
        kind, bank = KIND[prog.passes[pi].kind]
        ws = LS.s_words(t, kind)
        with open(os.path.join(outdir, f"smem_{pi}.txt"), "w") as fh:
            for a in range(256):
                w = ws.get(a, np.zeros(LS.WORD, np.uint8))
                fh.write(format(int.from_bytes(np.packbits(w, bitorder="little").tobytes(), "little"), "0512x") + "\n")
        f = LS.flags(t, kind)
        with open(os.path.join(outdir, f"flags_{pi}.txt"), "w") as fh:
            for i, v in enumerate(f):
                fh.write(f"{bank} {i} {int(v)}\n")


def write_sched(prog, log, outdir):
    lines, first = [], {}
    for seq, e in enumerate(log):
        pi = e["pi"]
        if pi not in first:
            first[pi] = e
            lines.append((e["cstart"] - 1, f"P {e['cstart'] - 1} {e['ctx']} {pi}"))
            p = prog.passes[pi]
            if p.inb == 8 and p.kind != "stem":
                kind, bank = KIND[p.kind]
                cyc = e["ra"] - LS.NFLAG[kind] - 2
                assert cyc >= 0, (pi, e["ra"])
                lines.append((cyc, f"F {cyc} {bank} {pi}"))
        lines.append((e["s"], f"T {e['s']} {e['ctx']} {pi} {e['tp']} {e['cg']}"))
    body = [l for _, l in sorted(lines, key=lambda x: x[0])]
    body += [f"L {e['pi']} {e['pos']} {e['ra']} {seq}" for seq, e in enumerate(log)]
    body += [f"X {e['pi']} {e['tp']} {e['cg']} {e['ce']}" for e in log]
    with open(os.path.join(outdir, "sched.txt"), "w") as fh:
        fh.write("\n".join(body) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("out")
    ap.add_argument("--images", type=int, nargs="+", default=[0, 1])
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--cache", required=True)
    a = ap.parse_args()
    dev = "cuda"
    prog, net, val, st, correct, mk = SU.load(a.ckpt, a.n, a.cache)
    rows, per, sup = SU.run(prog, st, mk, 2, CFG_C)
    xv, _ = val
    for i in a.images:
        od = os.path.join(a.out, f"img{i}")
        meta, n = EA.export_image(prog, net, xv[i:i + 1], od, dev)
        print(f"img{i}: {len(meta)} array passes, {n} items == export_core stim items (ctl + act): PASS", flush=True)
        write_s(prog, b6_sources(prog, xv[i:i + 1], dev), od)
        log = sup.final[i].log
        write_sched(prog, log, od)
        last = max(e["ce"] for e in log)
        print(f"img{i}: config C model {per[i]} cycles / image, {len(log)} array tiles, last item issue {last - 1}",
              flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
