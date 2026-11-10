"""Adder-tree operand toggles of the Kb = 2 ablation streams (mechanism check for results/ablation.md section 7.6):

    python3 -m qc18acc.ablation.operand_toggles <vec dir of vectors3.py>

Counts, per PE and cycle (mean over the 64 PEs and the 1152 steps of a point), the bit toggles of the operands that
enter the lane sums, from the vector files alone (no netlist):
  QC v3 (hw3 qa_pe_acc4): per lane 4 operands  u = (sext(e ? x_rot : 0) XOR {20{n}})  (e = t[0], n = t[1] & t[0]:
      negate = invert + carry-in, the carries as one small operand), 20 b each, plus the carry count;
  QC value form (for comparison): the same 4 terms as two's-complement values trit * x_rot (20 b);
  TERNARY: 16 operands per lane, the values trit_ij * x_j (21 b; how DC maps the behavioural trit select is not
      visible here, so this is the value-level count).
The x lanes, codes and trits are those of the stream files <v>_<L>.txt (one array step per line).
"""
import os
import sys

import numpy as np


def load(fn, wb):
    with open(fn) as f:
        S, T, WB, ACC, NS = map(int, f.readline().split())
        X, W = [], []
        for _ in range(NS):
            a, b = f.readline().split()
            X.append(int(a, 16))
            W.append(int(b, 16))
    assert WB == wb
    return X, W


def lanes(v, n, w, signed=True):
    out = [(v >> (w * i)) & ((1 << w) - 1) for i in range(n)]
    if w > 62:
        return out
    out = np.array(out, dtype=np.int64)
    if signed:
        out = np.where(out >= 1 << (w - 1), out - (1 << w), out)
    return out


def popcount(a):
    a = a.astype(np.uint64)
    c = np.zeros(a.shape, np.int64)
    while a.any():
        c += (a & np.uint64(1)).astype(np.int64)
        a >>= np.uint64(1)
    return c


def toggles(ops, bits):
    """ops [steps, ...] signed ints -> mean toggles per step summed over the trailing dims."""
    m = (1 << bits) - 1
    u = ops & m
    return popcount(u[1:] ^ u[:-1]).reshape(len(ops) - 1, -1).sum(1).mean()


def report(d):
    """-> {L: dict(qx, qv, tv, x, neg, xz)} toggles per PE-cycle (2 blocks)."""
    out = {}
    for L in ("L2", "L4"):
        X, Wq = load(os.path.join(d, f"qc_{L}.txt"), 20)
        _, Wt = load(os.path.join(d, f"tern_{L}.txt"), 256)
        ns = len(X)
        x = np.array([[lanes(xr, 16, 8) for xr in lanes(xx, 8, 128, False)] for xx in X])        # [s, p, 16]
        code = np.array([lanes(w, 8, 20, False) for w in Wq])                                       # [s, g]
        ii = np.arange(8)
        qx, qv, ncar = [], [], []
        for h in range(2):
            c = (code >> (10 * h)) & 1023
            for j in range(2):
                t = (c >> (5 * j)) & 3
                k = (c >> (5 * j + 2)) & 7
                e, n = t & 1, (t >> 1) & t & 1
                xs = x[:, :, 8 * h:8 * h + 8]                                                       # [s, p, 8]
                rot = np.take_along_axis(xs[:, :, None, :].repeat(8, 2),
                                         ((ii[None, :] + k[:, :, None]) % 8)[:, None, :, :].repeat(8, 1), 3)  # [s, p, g, i]
                v = rot * e[:, None, :, None]
                qx.append(np.where(n[:, None, :, None] == 1, ~v, v))
                qv.append(np.where(n[:, None, :, None] == 1, -v, v))
                ncar.append(n)
        qx, qv = np.stack(qx, -1), np.stack(qv, -1)                                                # [s, p, g, i, 4]
        tr = np.array([lanes(w, 8 * 2 * 64, 2, False).reshape(8, 2, 8, 8) for w in Wt])          # [s, g, h, i, j]
        tv = np.where(tr == 1, 1, np.where(tr == 3, -1, 0))
        xt = x.reshape(ns, 8, 2, 8)                                                                  # [s, p, h, j]
        to = tv[:, None] * xt[:, :, None, :, None, :]                                               # [s, p, g, h, i, j]
        per = 64.0
        out[L] = dict(qx=toggles(qx, 20) / per, qv=toggles(qv, 20) / per, tv=toggles(to, 21) / per,
                      x=toggles(x, 8) / 8, neg=float(np.mean(np.stack(ncar))), xz=float(np.mean(x == 0)))
    return out


def main():
    for L, r in report(sys.argv[1]).items():
        print(f"{L}: toggles per PE-cycle (2 blocks)  QC XOR-negate operands {r['qx']:.1f}  QC value operands "
              f"{r['qv']:.1f}  TERNARY value operands {r['tv']:.1f}  x lanes into the PE {r['x']:.1f}  "
              f"negative-trit share QC {r['neg']:.3f}  x zero share {r['xz']:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
