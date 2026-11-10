"""QC18-ACC v4 (16 pixel rows) compiler + golden check:
python3 -m qc18acc.compile4.main --ckpt RUN/best.pt [--n 1000] [--literal 4] [--acc] [--export DIR --images 0,1]
Prints the per-pass cycle MODEL for 16 and 32 PPU lanes and the lane decision of ARCH.md "v4" (keep 16 lanes if
they lose < 3 % of the cycles per image)."""
import argparse
import sys
import time

import numpy as np
import torch

from qc18.data import prep, test
from qc18acc.compile.program import BUFS, MODES
from qc18acc.compile.ref import build_intnet, maps
from qc18acc.compile3.golden import cycles as cycles3

from .export import export
from .golden import Golden4, act_reads, cycles
from .layout import BANKS, DEPTH, ROWS, cinp, join16, read_tensor, write_tensor
from .program import build

V3_MEASURED = 81438                                            # v3 RTL cycles / image (results/v3.md)
LANE_RULE = 0.03                                               # ARCH v4: keep 16 lanes if they lose < 3 %


def act_images(prog, q):
    t = prog.tensors["img"]
    act = np.zeros((q.shape[0], 3, BANKS * DEPTH, 2), np.uint64)
    x = np.zeros((q.shape[0], 8) + q.shape[2:], np.int64)
    x[:, :q.shape[1]] = q
    write_tensor(act[:, t.buf], x, t.lay, t.base)
    return act


def stored(prog, name, snap):
    t = prog.tensors[name]
    m = read_tensor(snap, t.lay, t.base, 8 * t.planes, t.H, t.W)
    return join16(m) if t.r16 else m.astype(np.int64)


def run_batch(net, prog, gold, x, check=True, literal=False):
    q, ref, p, acc = maps(net, x)
    act = act_images(prog, q.cpu().numpy())
    act0 = act.copy()
    logits, snaps, gp = gold.run(act, snap=check, literal=literal)
    ok = np.array_equal(logits, acc.cpu().numpy()) and np.array_equal(gp, p.cpu().numpy())
    bad = [ps.name for j, ps in enumerate(prog.passes)
           if check and not np.array_equal(stored(prog, ps.dst, snaps[j]), ref[ps.name].cpu().numpy())]
    return ok and not bad, bad, logits, acc, act0, snaps


def lanes_decision(images):
    c16, c32 = sum(cycles(images, 16)), sum(cycles(images, 32))
    loss = c16 / c32 - 1
    return c16, c32, loss, (16 if loss < LANE_RULE else 32)


def report(prog):
    c32, c16, c3 = cycles(prog.images, 32), cycles(prog.images, 16), cycles3(prog.images)
    print(f"{'pass':14s} {'mode':6s} {'k':>1s} {'s':>1s} {'in':>9s} {'out':>9s} {'buf':>5s} {'lay':>3s} {'S':>4s} "
          f"{'tiles':>5s} {'cyc32':>6s} {'cyc16':>6s} {'v3 mod':>6s}")
    for p, a, b, c in zip(prog.passes, c32, c16, c3):
        print(f"{p.name:14s} {MODES[p.mode]:6s} {p.k} {p.stride} {8 * p.cin8:3d}x{p.Hin:2d}x{p.Win:2d} "
              f"{64 * p.cout64:3d}x{p.Hout:2d}x{p.Wout:2d} {BUFS[p.in_buf]}>{BUFS[p.out_buf]}"
              f"{BUFS[p.res_buf] if p.res else ' '} {'RP'[p.in_lay]}{'RP'[p.out_lay]} {p.k * p.k * cinp(p.cin8):4d} "
              f"{p.Hout * p.Wout // ROWS * p.cout64:5d} {a:6d} {b:6d} {c:6d}")
    print(f"{'head':14s} {'':6s} {'':1s} {'':1s} {'':9s} {'':9s} {'':5s} {'':3s} {'':4s} {'':5s} {c32[-1]:6d} {c16[-1]:6d} {c3[-1]:6d}")
    pr = [p.proof for p in prog.passes]
    raw = [p.proof["y"] for p in prog.passes if MODES[p.mode] == "RAW16"]
    print(f"PROOF PASS (v3 proofs unchanged): max |acc| {max(r['acc'] for r in pr)} < 2^19, max |d acc + bias| "
          f"{max(r['v'] for r in pr)} < 2^19, max |R| {max(raw)} < 2^15; v4: all tensors fit 16 x 256 x 128 b, every "
          f"output map >= 16 pixels, drain pixel pairs (rows a, a + 2) in distinct banks in every out / res layout")
    s = prog.sizes()
    s["act_bytes"] = 3 * BANKS * DEPTH * 16
    print("memory: " + ", ".join(f"{k} {v}" for k, v in s.items()))
    ar = act_reads(prog.images)
    a16, a32, loss, choice = lanes_decision(prog.images)
    print(f"cycle MODEL v4: 32 PPU lanes {a32} cycles / image, 16 lanes {a16} (+{100 * loss:.1f} %); v3 model "
          f"{sum(c3)}, v3 measured {V3_MEASURED}; v4 (32) / v3 model {a32 / sum(c3):.3f}")
    print(f"LANES DECISION (ARCH v4: keep 16 if they lose < {100 * LANE_RULE:.0f} %): 16 lanes lose {100 * loss:.1f} % "
          f"-> {choice} lanes")
    print(f"array act-bank reads MODEL (128-b words): {sum(a for a, _ in ar)} / image (one per valid lane "
          f"{sum(b for _, b in ar)})")


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", default="/tmp/root/qc18/final/s8kd_s0/best.pt")
    ap.add_argument("--n", type=int, default=1000)
    ap.add_argument("--literal", type=int, default=4)
    ap.add_argument("--acc", action="store_true")
    ap.add_argument("--bs", type=int, default=100)
    ap.add_argument("--export", default="")
    ap.add_argument("--images", default="0,1,2,3")
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    net, model = build_intnet(a.ckpt, dev)
    prog = build(net, model)
    gold = Golden4(prog.images)
    print(f"{a.ckpt}: v4 (16 pixel rows x 8 columns, Kb = 2), {len(prog.passes)} passes + head")
    report(prog)
    xs, ys = test(dev)
    if a.n:
        t0, nb, nbad = time.time(), 0, 0
        for i in range(0, a.n, a.bs):
            j = min(a.n, i + a.bs)
            ok, bad, *_ = run_batch(net, prog, gold, prep(xs[i:j], torch.float64))
            nb += j - i
            nbad += 0 if ok else 1
            if not ok:
                print(f"MISMATCH batch {i}:{j}: {bad or 'logits/pool'}")
        if a.literal:
            ok_l, bad_l, *_ = run_batch(net, prog, gold, prep(xs[:a.literal], torch.float64), literal=True)
            print(f"literal 4-term PE path through the v4 16-slot kw window on {a.literal} images: "
                  f"{'PASS' if ok_l else 'FAIL ' + str(bad_l)}")
            nbad += 0 if ok_l else 1
        print(f"BIT-EXACT {'PASS' if nbad == 0 else 'FAIL'}: {nb} test images, int32 logits + pooled features + "
              f"all {len(prog.passes)} stored maps == IntNet ({time.time() - t0:.0f} s)")
    if a.acc:
        t0, cg, ci, same = time.time(), 0, 0, True
        for i in range(0, len(ys), 500):
            x = prep(xs[i:i + 500], torch.float64)
            _, _, lg, acc, *_ = run_batch(net, prog, gold, x, check=False)
            same &= np.array_equal(lg, acc.cpu().numpy())
            yy = ys[i:i + 500].cpu().numpy()
            cg += int(((lg * net.fscale.cpu().numpy()).argmax(1) == yy).sum())
            ci += int((net(x).argmax(1).cpu().numpy() == yy).sum())
        print(f"ACC: golden v4 {100 * cg / len(ys):.2f} %, IntNet {100 * ci / len(ys):.2f} % on {len(ys)} test images; "
              f"logits bit-exact on all: {same} ({time.time() - t0:.0f} s)")
    if a.export:
        ids = [int(v) for v in a.images.split(",")]
        ok, bad, lg, _, act0, snaps = run_batch(net, prog, gold, prep(xs[ids], torch.float64))
        assert ok, bad
        export(a.export, prog, act0, lg, snaps, ids)
        print(f"exported images {ids} to {a.export}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
