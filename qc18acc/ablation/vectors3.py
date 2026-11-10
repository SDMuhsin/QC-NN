"""Operand streams of the QC18-ACC array ablation at Kb = 2 (v3 array: two 8x8 blocks per PE per cycle):

    python3 -m qc18acc.ablation.vectors3 OUT_DIR [--img 0]

As vectors.py (Kb = 1), on the v3 data path: the v3 golden model (qc18acc/compile3/golden.py, Golden3) runs s8kd_s0
test image 0 up to the pass, then compile3.golden.gather_window gives exactly what the v3 xbar presents to array row
p in each step (128-b pair word: lanes 0..7 = input group 2j (even block), 8..15 = group 2j + 1 (odd block); v3 tap
order kh, j, kw).  Weights per step and column: even block = the v2 block of tap (kh, kw, 2j), odd = (kh, kw, 2j + 1)
(compile3.program.words3).  Same layers and the same tiles as Kb = 1 (so the same block-ops, now 2 per PE-cycle):
    L2 = blocks.3.c1 (S = 72 steps / tile, 16 tiles, 1152 steps), L4 = blocks.7.c1 (S = 288, 4 tiles, 1152 steps).
Per point a vector file <point>.txt (format of vectors.py; x row p = bits [128p+127:128p]):
    line 1: S T WB ACC NSTEP, then T*S lines <x 1024 b hex> <w 8*WB b hex>, then T*8 expected head lines.
Points: qc_<L> (20 b / column: even code [9:0], odd [19:10], ACC 20), tern_<L> (2 x 64 trits = 256 b, ACC 21),
int8_<L> (dense_s0, 2 x 64 int8 = 1024 b, ACC 32), int8c_<L> (the s8kd blocks as int8, control).
Checks: tern / int8c == qc, qc == the v3 golden pass accumulators (fp32 GEMM path) and == the Kb = 1 sums (vectors.py
order) of the same tiles.  Also writes stats.txt (v3 schedule: array steps / block-ops per image).
"""
import argparse
import os
import sys

import numpy as np
import torch

from qc18.data import prep, test
from qc18acc.compile import codes as K
from qc18acc.compile.layout import mcol
from qc18acc.compile.program import build as build2
from qc18acc.compile.ref import build_intnet, maps
from qc18acc.compile3.golden import Golden3, gather_window, lanes16
from qc18acc.compile3.layout import cinp, tap_order
from qc18acc.compile3.main import act_images
from qc18acc.compile3.program import from_v2, pass_codes

from .vectors import DENSE, LAYERS, S8KD, TRIT, dense_int8, hexw, pack

VARIANTS = {"qc": (20, 20), "tern": (256, 21), "int8": (1024, 32), "int8c": (1024, 32)}


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--img", type=int, default=0)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    net, model = build_intnet(S8KD, dev)
    prog2 = build2(net, model)
    prog = from_v2(prog2)
    gold = Golden3(prog.images)
    xs, _ = test(dev)
    q, *_ = maps(net, prep(xs[a.img:a.img + 1], torch.float64))
    act = act_images(prog, q.cpu().numpy())
    names = [p.name for p in prog.passes]
    stats = []
    S_ = {p.name: p.k * p.k * cinp(p.cin8) for p in prog.passes}
    steps = sum(p.Hout * p.Wout // 8 * p.cout64 * S_[p.name] for p in prog.passes)
    nw = sum(64 * p.cout64 * 8 * p.K for p in prog2.passes)
    stats.append(f"schedule array_steps {steps} block_ops {2 * 64 * steps} dense_macs {2 * 64 * 64 * steps} "
                 f"conv_weights {nw} qc_bits {nw // 64 * 10} tern_bits {nw * 2} int8_bits {nw * 8} "
                 f"sp28_bits {nw // 64 * 64}")
    done = 0
    for L, (name, tiles) in LAYERS.items():
        i = names.index(name)
        for j in range(done, i):
            gold.conv(act, j, gold.convs[j])
        done = i
        p, d, p2 = prog.passes[i], gold.convs[i], prog2.passes[i]
        S = S_[name]
        taps = tap_order(p.k, p.stride, p.cin8)
        assert len(taps) == S
        xw = gather_window(act[:, d.in_buf], d)[0].astype(np.int64)                 # [P, S, 16]
        # weights: v2 codes of the pass per og and v2 tap (kh, kw, cb); v3 step = (even 2j, odd 2j + 1)
        pc = pass_codes(prog2.images["weights"], p2)
        zero = np.zeros(8, np.int64)
        cds = np.array([[[pc[og][(kh, kw, 2 * jj + hh)] if (kh, kw, 2 * jj + hh) in pc[og] else zero
                          for hh in range(2)] for kh, kw, jj in taps] for og in range(p.cout64)])  # [og, S, h, g]
        kk, tt = K.decode(cds)                                                      # [og, S, h, g, 2]
        cf = K.coefs(kk, tt)                                                        # [og, S, h, g, s]
        ii = np.arange(8)
        Bq = cf[..., (ii[None, :] - ii[:, None]) % 8]                               # [og, S, h, g, i, j]
        # golden accumulators of the pass (v3 GEMM path) for the cross-check
        (pos, val), Wd, *_ = gold._pass_data(i, d)
        xg = lanes16(act[:, d.in_buf][:, pos]) * val[None, :, :, None]
        accg = (xg.reshape(-1, S * 16).astype(np.float64) @ Wd.astype(np.float64)).astype(np.int64)   # [P, Co]
        Md = dense_int8(name, 64 * p.cout64, 8 * p2.K)
        Md = Md.reshape(p.cout64, 8, 8, p2.K, 8)                                    # [og, g, i, mcol, j]
        Bd = np.zeros_like(Bq)
        for s, (kh, kw, jj) in enumerate(taps):
            for hh in range(2):
                cb = 2 * jj + hh
                if cb < p.cin8:
                    Bd[:, s, hh] = Md[:, :, :, mcol(p.k, p.cin8, kh, kw, cb), :]
        X = np.stack([xw[8 * t:8 * t + 8] for og, t in tiles]).reshape(len(tiles), 8, S, 2, 8)   # [T, p, S, h, j]
        res = {}
        for v, (wb, accb) in VARIANTS.items():
            B = Bd if v == "int8" else Bq
            Bt = np.stack([B[og] for og, t in tiles])                                # [T, S, h, g, i, j]
            acc = np.einsum("tshgij,tpshj->tpgi", Bt, X)                             # [T, p, g, i]
            assert np.abs(acc).max() < 2 ** (accb - 1), f"{v}: accumulator range"
            res[v] = acc
            with open(os.path.join(a.out, f"{v}_{L}.txt"), "w") as f:
                f.write(f"{S} {len(tiles)} {wb} {accb} {len(tiles) * S}\n")
                for n, (og, t) in enumerate(tiles):
                    for s in range(S):
                        x = pack([pack(X[n, r, s].reshape(-1), 8) for r in range(8)], 128)
                        if v == "qc":
                            w = pack([cds[og, s, 0, g] | (cds[og, s, 1, g] << 10) for g in range(8)], 20)
                        elif v == "tern":
                            w = pack([pack([TRIT[int(e)] for e in Bt[n, s, :, g].reshape(-1)], 2) for g in range(8)], 256)
                        else:
                            w = pack([pack(Bt[n, s, :, g].reshape(-1), 8) for g in range(8)], 1024)
                        f.write(f"{hexw(x, 1024)} {hexw(w, 8 * wb)}\n")
                for n in range(len(tiles)):
                    for r in range(8):
                        f.write(hexw(pack([pack(acc[n, r, g], accb) for g in range(8)], 8 * accb), 64 * accb) + "\n")
        for v in ("tern", "int8c"):
            assert np.array_equal(res[v], res["qc"]), f"{v} != qc"
        ref = np.stack([accg[8 * t:8 * t + 8, og * 64:(og + 1) * 64].reshape(8, 8, 8) for og, t in tiles])
        assert np.array_equal(res["qc"], ref), "qc stream != v3 golden pass accumulators"
        xz = (X == 0).mean()
        stats.append(f"{L} {name} S {S} tiles {len(tiles)} steps {len(tiles) * S} x_zero {xz:.3f} x_mean {X.mean():.2f} "
                     f"qc_zero_coef {(Bq == 0).mean():.4f} int8_zero {(Bd == 0).mean():.4f} "
                     f"int8_mean_abs {np.abs(Bd).mean():.2f} max_acc qc {np.abs(res['qc']).max()} int8 {np.abs(res['int8']).max()} "
                     f"golden_check PASS")
        print(stats[-1], flush=True)
    open(os.path.join(a.out, "stats.txt"), "w").write("\n".join(stats) + "\n")
    print(stats[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
