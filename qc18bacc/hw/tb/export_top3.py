#!/usr/bin/env python3
"""R3c: vectors of the image-to-logits bench of qb_chip (hw/rtl/qb_chip.sv: qb_top R3B + head qb_head).

    CUDA_VISIBLE_DEVICES=0 python3 qc18bacc/hw/tb/export_top3.py RUN/best.pt OUTDIR --cache DIR --images 0 1 2
    python3 qc18bacc/hw/tb/export_top3.py RUN/best.pt OUTDIR --cache DIR --images 0 1 2 --check   (after the bench)

Export: runs export_top2.main (network program in OUTDIR/prog, per-image img.txt / sched.txt / core / act), then adds
  prog/fc_rows.txt  FC macro rows (256 b = 4 x rf_sp 408 x 64 lanes; 1 613 rows): per group g of 8 classes one bias row
                    (8 x int32, class 8 g + n at bits [32 n +: 32]) then, per class j of the group, 16 weight rows
                    (chunk m: int8 W8[j, 32 m + n] at bits [8 n +: 8])
  prog/head.txt     head configuration words (qb_chip h_sel 17, address = index): 0 pool m0 (31 b), 1 pool sh, 2 last
                    pass index, 3 last-pass fused outputs (tiles x 4 steps), 4 stem pass index, 5 stem tile ends,
                    6 classes, 7 FC rows
  img<i>/logits.txt IntBin2 integer logits (igemm(pq, W8) + fbq, one decimal per class); IntBin2's float logits are
                    exactly these x fscale (asserted)
--check: reads img<i>/logits_rtl.txt (written by tb_qb_chip) and asserts torch.equal(rtl.double() * fscale,
  IntBin2(x)) per image.  Imports export_top2 / supply (nothing copied).
"""
import argparse
import os
import sys

import torch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from qc18bacc.compile import supply as SU  # noqa: E402
import export_top2 as ET2  # noqa: E402

LANES, DEPTH, NDEEP, ROWB = 4, 408, 4, 256          # FC macro: rf_sp 408 x 64 mux 4, 4 lanes x 4 deep


def fc_rows(net):
    W = net.fW8.long().cpu()
    b = net.fbq.long().cpu()
    nc, nk = W.shape
    assert nk % 32 == 0 and (W.abs() <= 127).all()
    assert (b.abs() + 512 * 127 * 127 < 2 ** 31).all(), "logit may overflow int32"
    rows = []
    for g in range(0, nc, 8):
        rows.append(sum((int(b[j]) & 0xFFFFFFFF) << (32 * (j - g)) for j in range(g, min(g + 8, nc))))
        for j in range(g, min(g + 8, nc)):
            for m in range(nk // 32):
                rows.append(sum((int(W[j, 32 * m + n]) & 0xFF) << (8 * n) for n in range(32)))
    assert len(rows) <= DEPTH * NDEEP
    return rows


def golden(net, xv, i):
    x = xv[i:i + 1]
    ref = net(x)[0]
    fs = net.fscale.double().to(ref.device)
    L = torch.round(ref / fs).long()
    assert torch.equal(L.double() * fs, ref), "IntBin2 logits are not integer x fscale"
    return ref, L, fs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("out")
    ap.add_argument("--images", type=int, nargs="+", default=[0, 1, 2])
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if not a.check:
        sys.argv = [sys.argv[0], a.ckpt, a.out, "--cache", a.cache, "--n", str(a.n), "--images", *map(str, a.images)]
        ET2.main()
    prog, net, val, st, correct, mk = SU.load(a.ckpt, a.n, a.cache)
    xv, _ = val
    if a.check:
        ok = True
        for i in a.images:
            ref, L, fs = golden(net, xv, i)
            with open(os.path.join(a.out, f"img{i}", "logits_rtl.txt")) as fh:
                r = torch.tensor([int(t) for t in fh.read().split()], dtype=torch.int64, device=ref.device)
            eq = r.numel() == ref.numel() and torch.equal(r.double() * fs, ref)
            ok &= eq
            print(f"R3C_CHECK {prog.run} val {i}: rtl logits x fscale == IntBin2 logits (torch.equal): "
                  f"{'PASS' if eq else 'FAIL'}; argmax {int(ref.argmax())}", flush=True)
        return 0 if ok else 1
    pd = os.path.join(a.out, "prog")
    rows = fc_rows(net)
    with open(os.path.join(pd, "fc_rows.txt"), "w") as fh:
        fh.writelines(format(r, "064x") + "\n" for r in rows)
    m0, sh = int(net.pool_m[0][0]), int(net.pool_m[1][0])
    assert net.pool_m[0].numel() == 1 and 0 < m0 < 2 ** 31 and 1 <= sh < 64
    last = len(prog.passes) - 1
    pl = prog.passes[last]
    stem = next(pi for pi, p in enumerate(prog.passes) if p.src == "IMG")
    ps = prog.passes[stem]
    assert pl.Hout * pl.Wout == 16 and pl.tiles_px == 1 and pl.cout == net.fW8.shape[1]
    cfg = [m0, sh, last, pl.tiles_px * (pl.cout // 64) * 4, stem, ps.tiles_px * (ps.cout // 64), net.fW8.shape[0],
           len(rows)]
    with open(os.path.join(pd, "head.txt"), "w") as fh:
        fh.write(f"{len(cfg)}\n" + "".join(format(v, "x") + "\n" for v in cfg))
    for i in a.images:
        ref, L, fs = golden(net, xv, i)
        with open(os.path.join(a.out, f"img{i}", "logits.txt"), "w") as fh:
            fh.write(" ".join(str(int(v)) for v in L.tolist()) + "\n")
    print(f"head: pool m0 {m0} sh {sh}, last pass {last} ({pl.name}), stem pass {stem}, FC rows {len(rows)}, "
          f"|fbq| max {int(net.fbq.abs().max())}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
