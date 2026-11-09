"""Operand streams of the QC18-ACC array ablation (qc18acc/ablation/README section in qc18acc/README.md):

    python3 -m qc18acc.ablation.vectors OUT_DIR [--img 0]

The activations are the REAL v2 array inputs of s8kd_s0, test image 0: the golden model (qc18acc/compile/golden.py)
runs the network up to the pass, then golden.gather_window gives exactly what the v2 xbar presents to array row p in
each step (v2 tap order kh, cb, kw; kw window; padding lanes zeroed).  The QC codes are the pass's v2 weight words
(same order).  Per point a vector file <point>.txt:
    line 1:        K T WB ACC NSTEP                     (WB = weight bits per column, ACC = accumulator bits)
    T*K lines:     <x 512 b hex> <w 8*WB b hex>        (one array step; x row p = bits [64p+63:64p])
    T*8 lines:     expected array heads after the tile's capture, drain row p = 0..7 (8 columns x 8 lanes x ACC b)
Points (L2 = blocks.3.c1, K = 144, 16 tiles; L4 = blocks.7.c1, K = 576, 4 tiles; 2304 steps each):
    qc_<L>     QC codes (10 b / column)                        ACC 20
    tern_<L>   the same blocks expanded to 64 trits (2 b each)   ACC 21   (same math as qc_<L>)
    int8_<L>   dense_s0 weights of the same layer (BN folded, per-output-channel symmetric int8)   ACC 32
    int8c_<L>  the s8kd blocks as int8 (control: same math as qc_<L>)                              ACC 32
Expected heads = numpy int64 reference (sum_s B_s x_s per PE), checked in range; qc / tern / int8c must agree, and
the qc sums must equal the golden model's own per-pass accumulators (fp32 GEMM path) for those pixels / channels.
Also writes stats.txt (weight / activation statistics, block-ops per image of the v2 schedule).
"""
import argparse
import os
import sys

import numpy as np
import torch

from qc.structure import to_matrix
from qc18.data import prep, test
from qc18.verify import fold, load
from qc18acc.compile import codes as K
from qc18acc.compile.golden import Golden, gather_window
from qc18acc.compile.layout import mcol, tap_order, words_to_lanes
from qc18acc.compile.main import act_images
from qc18acc.compile.program import build
from qc18acc.compile.ref import build_intnet, maps

S8KD = "/tmp/root/qc18/final/s8kd_s0/best.pt"
DENSE = "/tmp/root/qc18/final/dense_s0/best.pt"
LAYERS = {"L2": ("blocks.3.c1", [(og, t) for og in range(2) for t in range(0, 32, 4)]),   # 16 tiles
          "L4": ("blocks.7.c1", [(og, t) for og in (0, 4) for t in range(2)])}           # 4 tiles
VARIANTS = {"qc": (10, 20), "tern": (128, 21), "int8": (512, 32), "int8c": (512, 32)}
TRIT = {0: 0, 1: 1, -1: 3}


def hexw(v, bits):
    return f"{v & ((1 << bits) - 1):0{bits // 4 + (bits % 4 > 0)}x}"


def pack(vals, w):
    """ints (lane 0 first) -> one int, lane n at bits [n w + w - 1 : n w] (two's complement)."""
    m, r = (1 << w) - 1, 0
    for n, v in enumerate(vals):
        r |= (int(v) & m) << (n * w)
    return r


def dense_int8(name, cout, nk):
    """dense_s0 conv of the layer, BN folded (qc18.verify.fold), per-output-channel symmetric int8, as the
    [cout, k*k*cin] matrix in the QC column order (qc.structure.to_matrix 'hwc' = mcol order)."""
    _, model = load(DENSE, "cpu")
    cb = dict(model.convbns())[name]
    s, _ = fold(cb.bn)
    W = (cb.conv.weight.double() * s.double()[:, None, None, None]).detach()
    M = to_matrix(W, 8).numpy()
    assert M.shape == (cout, nk)
    sc = np.abs(M).max(1, keepdims=True) / 127.0
    return np.clip(np.round(M / sc), -127, 127).astype(np.int64)


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
    prog = build(net, model)
    gold = Golden(prog.images)
    xs, _ = test(dev)
    q, *_ = maps(net, prep(xs[a.img:a.img + 1], torch.float64))
    act = act_images(prog, q.cpu().numpy())
    names = [p.name for p in prog.passes]
    stats = []
    # block-ops of the v2 schedule (one image): per pass tiles x K steps, 64 PEs per step
    steps = sum(p.Hout * p.Wout // 8 * p.cout64 * p.K for p in prog.passes)
    nw = sum(64 * p.cout64 * 8 * p.K for p in prog.passes)
    stats.append(f"schedule array_steps {steps} block_ops {64 * steps} dense_macs {64 * 64 * steps} "
                 f"conv_weights {nw} qc_bits {nw // 64 * 10} tern_bits {nw * 2} int8_bits {nw * 8}")
    done = 0
    for L, (name, tiles) in LAYERS.items():
        i = names.index(name)
        for j in range(done, i):
            gold.conv(act, j, gold.convs[j])
        done = i
        p, d = prog.passes[i], gold.convs[i]
        Kb = p.K
        xw = gather_window(act[:, d.in_buf], d)[0]                                  # [P, Kb, 8] int8
        cds = K.word_codes(prog.images["weights"][p.wbase:p.wbase + p.cout64 * Kb]).reshape(p.cout64, Kb, 8)
        kk, tt = K.decode(cds)                                                      # [og, Kb, g, 2]
        cf = K.coefs(kk, tt)                                                        # [og, Kb, g, s]
        ii = np.arange(8)
        Bq = cf[:, :, :, (ii[None, :] - ii[:, None]) % 8]                           # [og, Kb, g, i, j] = c[(j-i)%8]
        # golden accumulators of the pass (GEMM path) for the cross-check
        (pos, val), Wd, *_ = gold._pass_data(i, d)
        xg = words_to_lanes(act[:, d.in_buf][:, pos]) * val[None, :, :, None]
        accg = (xg.reshape(-1, Kb * 8).astype(np.float64) @ Wd.astype(np.float64)).astype(np.int64)  # [P, Co]
        Md = dense_int8(name, 64 * p.cout64, 8 * Kb)
        cols = [mcol(p.k, p.cin8, kh, kw, cb) for kh, kw, cb in tap_order(p.k, p.stride, p.cin8)]
        Bd = Md.reshape(p.cout64, 8, 8, Kb, 8)[:, :, :, cols, :].transpose(0, 3, 1, 2, 4)   # [og, Kb, g, i, j]
        X = np.stack([xw[8 * t:8 * t + 8] for og, t in tiles]).astype(np.int64)    # [T, 8p, Kb, 8j]
        res = {}
        for v, (wb, accb) in VARIANTS.items():
            B = Bd if v == "int8" else Bq
            Bt = np.stack([B[og] for og, t in tiles])                                # [T, Kb, g, i, j]
            acc = np.einsum("tsgij,tpsj->tpgi", Bt, X)                               # [T, p, g, i]
            assert np.abs(acc).max() < 2 ** (accb - 1), f"{v}: accumulator range"
            res[v] = acc
            with open(os.path.join(a.out, f"{v}_{L}.txt"), "w") as f:
                f.write(f"{Kb} {len(tiles)} {wb} {accb} {len(tiles) * Kb}\n")
                for n, (og, t) in enumerate(tiles):
                    for s in range(Kb):
                        x = pack([pack(X[n, r, s], 8) for r in range(8)], 64)
                        if v == "qc":
                            w = pack(cds[og, s], 10)
                        elif v == "tern":
                            w = pack([pack([TRIT[int(e)] for e in Bt[n, s, g].reshape(-1)], 2) for g in range(8)], 128)
                        else:
                            w = pack([pack(Bt[n, s, g].reshape(-1), 8) for g in range(8)], 512)
                        f.write(f"{hexw(x, 512)} {hexw(w, 8 * wb)}\n")
                for n in range(len(tiles)):
                    for r in range(8):
                        f.write(hexw(pack([pack(acc[n, r, g], accb) for g in range(8)], 8 * accb), 64 * accb) + "\n")
        for v in ("tern", "int8c"):
            assert np.array_equal(res[v], res["qc"]), f"{v} != qc"
        ref = np.stack([accg[8 * t:8 * t + 8, og * 64:(og + 1) * 64].reshape(8, 8, 8) for og, t in tiles])
        assert np.array_equal(res["qc"], ref), "qc stream != golden pass accumulators"
        xz = (X == 0).mean()
        stats.append(f"{L} {name} K {Kb} tiles {len(tiles)} steps {len(tiles) * Kb} x_zero {xz:.3f} x_mean {X.mean():.2f} "
                     f"qc_zero_coef {(Bq == 0).mean():.4f} int8_zero {(Bd == 0).mean():.4f} "
                     f"int8_mean_abs {np.abs(Bd).mean():.2f} max_acc qc {np.abs(res['qc']).max()} int8 {np.abs(res['int8']).max()} "
                     f"golden_check PASS")
        print(stats[-1], flush=True)
    open(os.path.join(a.out, "stats.txt"), "w").write("\n".join(stats) + "\n")
    print(stats[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
