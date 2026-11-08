"""Integer-exact int8 inference of a verified qc18 QC checkpoint:  python3 -m qc18.int8 RUN/best.pt [--test]

Weights.  Conv: int8 weight = sign(s_c) * M (M = the stored QC matrix, entries -1/0/1, incl. the stem's
zero-padded input channels, which multiply zero inputs); the folded BN scale s_c (qc18.verify.fold) becomes the
symmetric per-output-channel weight scale |s_c|, the folded BN bias an int32 bias round(bias / (S_in |s_c|)).
QC proof: decompose(to_matrix(W_int8) * sign(s_c)) re-expands to M.  FC: int8 with symmetric per-output-channel
scale max|w_row| / 127, int32 bias round(b / (S_pool s_w)).
Activations.  int8 with per-tensor symmetric scales S = max|a| / 127 calibrated on the float model over a fixed
train subset (the first --calib images of the 45k train split, no augmentation; never val/test): the input, each
ReLU output (stem, block c1) and each block output, and the pooled features.  Post-ReLU tensors use [0, 127].
The input quantisation round(x_norm / S_0) is the only float op before the logits (a per-channel 256-entry LUT
of the uint8 pixel in hardware).
Arithmetic.  Convs/FC: integer products, int32 accumulation (+ int32 bias); conv sums are computed as fp64 GEMMs
of integer tensors (exact, |acc| < 2^53) and every accumulator is checked to fit int32.
Requant (per output channel): fixed-point multiplier + shift, y = (v * m0 + 2^(sh-1)) >> sh with
m0 in [2^30, 2^31) a 31-bit integer, 1 <= sh <= 62, m = m0 2^-sh ~ S_in |s_c| / S_out (int64 product; round half
up), then clamp ([-127, 127], or [0, 127] with the ReLU folded in).
Residual add: both branches are requantised to the block-output scale S_o in int32 without clamping (c2: its
accumulator with m = S_mid |s_c2| / S_o; identity shortcut: the int8 input with m = S_in / S_o; conv shortcut:
its accumulator with m = S_in |s_sc| / S_o), added in int32, then ReLU + clamp to [0, 127] -> int8.
Global pool: int32 sum over the 4x4 positions, requantised with m = S_o / (16 S_pool) to int8 [0, 127].
Logits: int32 FC accumulator * (S_pool s_w) (float dequant, per class) -> argmax.
Output <run>/int8.txt.  Test is evaluated only with --test (once, at the end; refused if int8.txt already holds a
test result unless --force).
"""
import argparse
import math
import os
import sys

import torch
import torch.nn.functional as F

from qc.structure import cin_pad, decompose, expand, to_matrix

from .data import prep, split, test
from .train import accuracy
from .verify import fold, load

I32 = 2 ** 31


def fixmul(m):
    """Positive multipliers m [C] (float64) -> (m0, sh) int64 with m ~ m0 * 2^-sh, m0 in [2^30, 2^31), 1<=sh<=62.
    m < 2^-32 (contribution below half an LSB for any int32 input < 2^31) -> m0 = 0."""
    m = torch.as_tensor(m, dtype=torch.float64).flatten()
    m0, sh = torch.zeros_like(m, dtype=torch.int64), torch.ones_like(m, dtype=torch.int64)
    for i, v in enumerate(m.tolist()):
        assert v > 0 and math.isfinite(v), f"bad multiplier {v}"
        f, e = math.frexp(v)                                   # v = f 2^e, f in [0.5, 1)
        q = round(f * 2 ** 31)
        if q == 2 ** 31:
            q, e = 2 ** 30, e + 1
        s = 31 - e
        assert s >= 1, f"multiplier {v} too large"
        if s > 62:
            q, s = 0, 1
        m0[i], sh[i] = q, s
    return m0, sh


def requant(v, m0, sh, lo=None, hi=None):
    """(v * m0 + 2^(sh-1)) >> sh per channel (dim 1), int64; optional clamp."""
    assert v.dtype == torch.int64 and v.abs().max() < I32, "int32 overflow"
    shape = (1, -1) + (1,) * (v.dim() - 2)
    m0, sh = m0.to(v.device).view(shape), sh.to(v.device).view(shape)
    y = torch.bitwise_right_shift(v * m0 + torch.bitwise_left_shift(torch.ones_like(sh), sh - 1), sh)
    return y if lo is None else y.clamp(lo, hi)


def igemm(fn, q, w):
    """Exact integer conv / linear: fp64 of int tensors -> int64, checked to fit int32."""
    a = fn(q.double(), w.double())
    r = a.round()
    assert torch.equal(r, a) and r.abs().max() < I32, "accumulator not exact / overflows int32"
    return r.long()


class IntConv:
    """One ConvBN as int8 weights sign(s) M, per-channel scale |s|, int32 bias (scale S_in |s|)."""

    def __init__(self, cb, S_in, signed):
        conv = cb.conv
        self.stride, self.padding, b = conv.stride, conv.padding, conv.b
        s, bias = (t.double() for t in fold(cb.bn))
        assert torch.isfinite(s).all() and (s != 0).all(), "BN scale zero / not finite"
        M = conv.matrix().double()                                       # [cout, k*k*cin_pad], entries -1/0/1
        cout, k, self.cp = M.shape[0], conv.k, cin_pad(conv.cin, b)
        d = torch.sign(s)
        W = M.reshape(cout, k, k, self.cp).permute(0, 3, 1, 2)          # all cin_pad input channels
        self.W8 = (d[:, None, None, None] * W).to(torch.int8)
        assert torch.equal(self.W8.double(), d[:, None, None, None] * W)
        # QC proof on the int8 weights
        Mq = to_matrix(self.W8.double() * d[:, None, None, None].to(self.W8.device), b)
        C = decompose(Mq, b, signed=signed)
        assert torch.equal(expand(torch.as_tensor(C, dtype=torch.float64, device=Mq.device), b), Mq), "re-expansion"
        assert torch.equal(Mq, M), "int8 weights / sign(s) != QC matrix"
        self.flips, self.shape = int((d < 0).sum()), tuple(Mq.shape)
        self.sw = s.abs()                                                # per-channel weight scale
        self.eff = S_in * self.sw                                       # accumulator scale
        bq = torch.round(bias / self.eff)
        assert bq.abs().max() < I32, "bias overflows int32"
        self.bq = bq.long()

    def acc(self, q):
        if q.shape[1] < self.cp:
            q = F.pad(q, (0, 0, 0, 0, 0, self.cp - q.shape[1]))
        fn = lambda x, w: F.conv2d(x, w, stride=self.stride, padding=self.padding)
        return igemm(fn, q, self.W8) + self.bq[None, :, None, None]

    def mult(self, S_out):
        return fixmul(self.eff / S_out)


@torch.no_grad()
def float_acts(model, x):
    """Float (fp32 model) activations at the quantisation points, in network order."""
    out = [x]
    h = F.relu(model.stem(x))
    out.append(h)
    for blk in model.blocks:
        t = F.relu(blk.c1(h))
        h = F.relu(blk.c2(t) + (blk.sc(h) if blk.sc is not None else h))
        out += [t, h]
    out.append(h.mean(dim=(2, 3)))
    return out


class IntNet:
    def __init__(self, model, S, signed):
        """S: per-tensor scales [input, stem, (c1, block out) x 8, pool] (float64)."""
        S = [float(v) for v in S]
        self.S0, it = S[0], iter(S[1:])
        self.layers = {}
        s_stem = next(it)
        self.stem = IntConv(model.stem, self.S0, signed)
        self.stem_m = self.stem.mult(s_stem)
        self.layers["stem"] = self.stem
        self.blocks, s_in = [], s_stem
        for i, blk in enumerate(model.blocks):
            s_mid, s_o = next(it), next(it)
            c1 = IntConv(blk.c1, s_in, signed)
            c2 = IntConv(blk.c2, s_mid, signed)
            e = dict(c1=c1, c1m=c1.mult(s_mid), c2=c2, c2m=c2.mult(s_o))
            if blk.sc is not None:
                e["sc"] = IntConv(blk.sc, s_in, signed)
                e["scm"] = e["sc"].mult(s_o)
                self.layers[f"blocks.{i}.sc"] = e["sc"]
            else:
                e["idm"] = fixmul(torch.tensor([s_in / s_o]))
            self.layers[f"blocks.{i}.c1"], self.layers[f"blocks.{i}.c2"] = c1, c2
            self.blocks.append(e)
            s_in = s_o
        s_p = next(it)
        self.pool_m = fixmul(torch.tensor([s_in / (16 * s_p)]))
        W = model.fc.weight.detach().double()
        self.fsw = W.abs().amax(1) / 127
        self.fW8 = torch.round(W / self.fsw[:, None]).clamp(-127, 127).to(torch.int8)
        self.fbq = torch.round(model.fc.bias.detach().double() / (s_p * self.fsw)).long()
        self.fscale = s_p * self.fsw

    def __call__(self, x):
        q = torch.round(x.double() / self.S0).clamp(-127, 127).long()       # input quantisation
        q = requant(self.stem.acc(q), *self.stem_m, 0, 127)
        for e in self.blocks:
            t = requant(e["c1"].acc(q), *e["c1m"], 0, 127)
            r = requant(e["c2"].acc(t), *e["c2m"])
            r = r + (requant(e["sc"].acc(q), *e["scm"]) if "sc" in e else requant(q, *e["idm"]))
            q = r.clamp(0, 127)
        assert q.shape[2:] == (4, 4)
        p = requant(q.sum(dim=(2, 3)), *self.pool_m, 0, 127)
        acc = igemm(F.linear, p, self.fW8) + self.fbq
        return acc.double() * self.fscale                                   # dequantised logits


def int_accuracy(net, x, y, bs=500):
    return sum((net(prep(x[i:i + bs], torch.float64)).argmax(1) == y[i:i + bs]).sum().item()
               for i in range(0, len(y), bs)) / len(y)


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--calib", type=int, default=2000, help="first N images of the train split for calibration")
    ap.add_argument("--test", action="store_true", help="evaluate the test set (once, at the end)")
    ap.add_argument("--force", action="store_true", help="allow --test although int8.txt has a test result")
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    out_path = os.path.join(os.path.dirname(os.path.abspath(a.ckpt)), "int8.txt")
    if a.test and not a.force and os.path.exists(out_path) and "test accuracy" in open(out_path).read():
        print(f"refusing: {out_path} already holds a test evaluation (--force to override)")
        return 1
    ck, model = load(a.ckpt, dev)
    args = ck["args"]
    if args["mode"] == "dense" or args.get("relax", "none") != "none":
        print("FAIL: not a QC checkpoint")
        return 1
    signed = args["mode"] == "signed"
    lines = []
    log = lambda s: (print(s), lines.append(s))
    (xt, _), (xv, yv) = split(dev)
    xc = prep(xt[:a.calib])
    mx = None
    for i in range(0, len(xc), 500):
        m = [t.abs().amax().double() for t in float_acts(model, xc[i:i + 500])]
        mx = m if mx is None else [torch.maximum(u, v) for u, v in zip(mx, m)]
    S = [v.item() / 127 for v in mx]
    net = IntNet(model, S, signed)
    log(f"{a.ckpt}: mode {args['mode']}, b {args['b']}, epoch {ck['epoch']}; int8 integer-exact inference")
    log(f"calibration: max|a|/127 per tensor on train[:{a.calib}]; input S {S[0]:.4g}, pool S {S[-1]:.4g}")
    ok = True
    for n, c in net.layers.items():
        log(f"{n:16s} int8 {tuple(c.W8.shape)} -> matrix {c.shape}  QC PASS  ({c.flips} sign-flipped rows)")
    zero_m = sum(int((e[k][0] == 0).sum()) for e in net.blocks for k in ("c1m", "c2m", "scm") if k in e)
    log(f"weights: all conv int8 weights in {{-1,0,1}} = sign(s_c) M, decompose PASS; FC int8 per-channel; "
        f"{zero_m} requant multipliers < 2^-32 set to 0")
    vf = accuracy(model, xv, yv)
    vq = int_accuracy(net, xv, yv)
    log(f"val accuracy: float model (fp32) {100 * vf:.2f} %, int8 {100 * vq:.2f} %")
    if a.test:
        xs, ys = test(dev)
        log(f"test accuracy: int8 {100 * int_accuracy(net, xs, ys):.2f} %")
    log("INT8 PASS" if ok else "INT8 FAIL")
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
