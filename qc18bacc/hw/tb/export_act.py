#!/usr/bin/env python3
"""Per-pass stimulus + expected item / act stream of qb_act (hw/rtl/qb_act.sv) for whole images, from the bit-exact
dataflow model (compile/dataflow.py, golden p2), cross-checked against export_core.py's qb_core stimulus:

    CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_act.py RUN/best.pt OUTDIR [--images 0 1]

Per image i (val[i], never the test set) and array pass pi: OUTDIR/img<i>/
  mem_<pi>.txt   source map before the pass in the map-macro layout (compile/layout.py): one 512-b line per text
                 line (hex, line bit 0 = LSB; macro m = bits 128 m ..; line bit 7 of the address = map for HQ)
  exp_<pi>.txt   expected act-port stream in order: 'I first plane neg stem g3n chunk ct tile act_hex' per item
                 (act bit 288 r + 32 tap + k, as export_core), 'E ct tile' at the end of every (tile, channel tile)
  passes_act.txt 'pi name cfg nchunk nct ntile int8 stem nlines nitems'
The concatenated item stream (ctl fields + act) of all passes is asserted equal to the item stream of export_core's
stim.txt (ctl valid cycles, act one cycle later) for the same image, so the bench compares against export_core's
stimulus.
"""
import argparse
import os
import sys
import tempfile

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402
import torch  # noqa: E402

from qc18bacc.compile import dataflow as D  # noqa: E402
from qc18bacc.compile import layout as LY  # noqa: E402
from qc18bacc.compile import program as P  # noqa: E402
import export_core as EC  # noqa: E402

CFG = {(32, 1, 3): 0, (32, 2, 3): 2, (32, 2, 1): 3, (16, 1, 3): 4, (16, 2, 3): 5, (16, 2, 1): 6, (8, 1, 3): 7,
       (8, 2, 3): 8, (8, 2, 1): 9, (4, 1, 3): 10}


def items_of(p, before):
    """[(tile, [(ct-independent) (first?, plane, neg, stem, g3n, chunk, act [16, 288])])] as export_core."""
    L, Li = p.Hout * p.Wout, p.Hin * p.Win
    w = EC._wrap(before)
    if p.inb == 8:
        C = 8 if p.src == "IMG" else p.cin
        planes = [(D.nchw(D.Bufs.read(w, p.src, Li, C, plane=b), p.Hin, p.Win).float(), b == 7) for b in range(8)]
    else:
        planes = [(D.nchw(D.Bufs.read(w, p.src, Li, p.cin), p.Hin, p.Win).float(), False)]
    out = []
    if p.p.get("pack"):
        pt = []
        for h in range(2):
            a = torch.cat([D.patches(planes[4 * h + gg][0], p)[:, :, 0].view(1, L, 9, P.CH)[..., :8]
                           for gg in range(4)], -1).reshape(1, L, 9 * P.CH)
            pt.append(a[0].cpu().numpy().astype(np.uint8))
        for tp in range(p.tiles_px):
            out.append([(4 * h, 0, 1, int(h == 1), h, pt[h][16 * tp:16 * tp + 16]) for h in range(2)])
        return out
    pts = [D.patches(a, p)[0].cpu().numpy().astype(np.uint8) for a, _ in planes]
    skip = p.inb == 8
    for tp in range(p.tiles_px):
        its = []
        for pl, (_, neg) in enumerate(planes):
            for c in range(p.nchunk):
                a = pts[pl][16 * tp:16 * tp + 16, c]
                if skip and not a.any():
                    continue
                its.append((pl, int(neg), 0, 0, c, a))
        if not its:
            its.append((0, 0, 0, 0, 0, np.zeros((16, P.KB * 8), np.uint8)))
        out.append(its)
    return out


def stim_items(path):
    """export_core stim.txt -> [(ctl & 0xff, act int)] of the valid item cycles (act one cycle after ctl)."""
    rows = [ln.split() for ln in open(path)]
    out = []
    for t, r in enumerate(rows):
        c = int(r[0], 16)
        if c & 1:
            out.append((c & 0xFF, int(rows[t + 1][2], 16)))
    return out


def export_image(prog, net, x, outdir, dev):
    Ws = {p.name: D.PEWeights(p, dev) for p in prog.passes if p.k}
    bf = D.Bufs(1, dev)
    D.load_image(prog, bf, x, dev)
    os.makedirs(outdir, exist_ok=True)
    meta, seq = [], []
    for pi, p in enumerate(prog.passes):
        before = {k: v.clone() for k, v in bf.b.items()}
        p.p["dev"] = dev
        D.do_pass(prog, p, bf, Ws, dev, {})
        if not p.k:
            continue
        assert p.pad == (1 if p.k == 3 else 0) and p.Hin == p.Win
        cfg = CFG[p.Win, p.stride, p.k]
        planes, H, W, C, img = LY.src_geom(p)
        src = before[p.src][0].cpu().numpy()
        n = (8 * H * W * 8) if img else planes * H * W * C
        assert (src[:n] >= 0).all()
        lines = LY.to_lines(src[:n], planes, H, W, C, img)
        with open(os.path.join(outdir, f"mem_{pi}.txt"), "w") as fh:
            for ln in lines:
                v = int.from_bytes(np.packbits(ln, bitorder="little").tobytes(), "little")
                fh.write(format(v, "0128x") + "\n")
        its = items_of(p, before)
        nct = p.cout // 64
        nit = 0
        with open(os.path.join(outdir, f"exp_{pi}.txt"), "w") as fh:
            for tp, lst in enumerate(its):
                for ct in range(nct):
                    for k, (pl, neg, stem, g3n, ch, a) in enumerate(lst):
                        act = EC.pack_bits(a)
                        fh.write(f"I {int(k == 0)} {pl} {neg} {stem} {g3n} {ch} {ct} {tp} {act:x}\n")
                        seq.append((EC.ctlw(valid=1, first=int(k == 0), plane=pl, neg=neg, stem=stem, g3n=g3n), act))
                        nit += 1
                    fh.write(f"E {ct} {tp}\n")
        int8 = int(p.inb == 8 and p.src != "IMG")
        nch = 2 if p.p.get("pack") else p.nchunk               # stem: 2 chunks h = planes 4h..4h+3
        meta.append(f"{pi} {p.name} {cfg} {nch} {nct} {p.tiles_px} {int8} {int(p.src == 'IMG')} {len(lines)} {nit}")
    with open(os.path.join(outdir, "passes_act.txt"), "w") as fh:
        fh.write("\n".join(meta) + "\n")
    # cross-check vs export_core's stimulus
    with tempfile.TemporaryDirectory() as td:
        EC.export_image(prog, net, x, td, dev)
        ref = stim_items(os.path.join(td, "stim.txt"))
    assert len(ref) == len(seq), (len(ref), len(seq))
    assert ref == seq, "item stream != export_core stim"
    return meta, len(seq)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("out")
    ap.add_argument("--images", type=int, nargs="+", default=[0, 1])
    a = ap.parse_args()
    dev = "cuda"
    prog, net, (xv, yv) = P.build_program(a.ckpt, dev, v=11)
    for i in a.images:
        x = xv[i:i + 1]
        meta, n = export_image(prog, net, x, os.path.join(a.out, f"img{i}"), dev)
        print(f"img{i}: {len(meta)} array passes, {n} items == export_core stim items (ctl + act): PASS", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
