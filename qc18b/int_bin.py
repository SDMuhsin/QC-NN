"""Integer-exact inference of a verified binary-activation qc18b checkpoint (style of qc18.int8):
    CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.int_bin RUN/best.pt [--test]

Network and folding: qc18b.verify_bin (build, Folded: QC matrices M, BN fold g/h, b2 thresholds sigma/T).
Weights.  Every conv: integer weight sign(g) M in {-1,0,1} (qc18.int8.IntConv: re-proved QC, decompose + re-expand == M),
so every accumulator acc' = sign(g) M x and the per-channel scale |g| is positive.
Input.  As qc18.int8: q0 = clamp(round(x_norm / S_in), -127, 127), S_in = max|x_norm| / 127 on train[:calib].
Accumulators.  int32 (exact fp64 GEMMs of integer tensors, checked < 2^31): 1-bit {0,1} inputs for binary convs (c1, c2, sc
of binary blocks), int8 inputs for the stem and the --fp-blocks convs.
Residual stream.  s_k (stem output and each block output, pre-ReLU) is int16 with per-tensor symmetric scale
S_k = max|s_k| / 32767 calibrated on the folded fp64 network over train[:calib] (never val/test); saturating clamp to
[-32767, 32767] after the residual add (saturations counted).
Requant into the stream (qc18.int8.fixmul / requant: y = (v m0 + 2^(sh-1)) >> sh, m0 31-bit, round half up):
  int8-input convs (stem, fp-block c2/sc): int32 bias round(h / (S_x |g|)) added to the accumulator (as qc18.int8),
    then m = S_x |g| / S_k.
  binary-input convs (c2, sc): the accumulator LSB is |g| (input scale 1), so the bias is added at the stream scale:
    y = requant(acc', m = |g| / S_k) + round(h / S_k).
  identity shortcut relu(s_in): requant(max(s_in, 0), m = S_{k-1} / S_k).
b1 = 1[s > t] on the stream:  s_int S_k > t  <=>  s_int > t / S_k  <=>  s_int > T1,  T1 = floor(t / S_k) (fp64), s_int integer.
b2 = 1[sigma acc >= T] (verify_bin.fold_b2) on the c1 accumulator acc' = sign(g) M b1 (no requant).
fp blocks: relu(s_in) -> int8 [0,127] at S_h (requant m = S_{k-1} / S_h), c1 -> relu int8 [0,127] at S_mid (as qc18.int8),
  S_h / S_mid = max / 127 on calib.
Pool: int32 sum of relu(s_7) over the 4x4 positions, requant m = S_7 / (16 S_pool) to int8 [0,127]; FC int8 per-channel
  (qc18.int8.IntNet FC construction), int32 bias, logits = acc * S_pool s_w (float dequant) -> argmax.
Reports val accuracy folded fp64 (verify_bin.Folded) vs integer, argmax differences, per-layer 1-bit disagreement on the
first 500 val images; --test (once) adds integer test accuracy.  Output <run>/intbin.txt.
"""
import argparse
import math
import os
import sys

import torch
import torch.nn.functional as F

from qc18.int8 import I32, IntConv, fixmul, igemm, requant

from . import data
from .verify_bin import Folded, build

Q16 = 32767


class IntBin:
    def __init__(self, model, fn, S, signed):
        """S: dict of calibration maxima (float): 'in', 's0'.., 'h{i}'/'m{i}' (fp blocks), 'pool'."""
        self.fn, self.fpb = fn, fn.fpb
        self.S = S0 = {k: v / (32767 if k.startswith("s") else 127) for k, v in S.items()}
        self.ic = {}                                                       # integer conv weights (QC re-proved)
        self.ic["stem"] = IntConv(model.stem, 1.0, signed)
        for i, blk in enumerate(model.blocks):
            for c in ("c1", "c2", "sc"):
                if getattr(blk, c) is not None:
                    self.ic[f"blocks.{i}.{c}"] = IntConv(getattr(blk, c), 1.0, signed)
        self.sat = 0
        g = lambda n: fn.fold[n]["g"].abs()
        h = lambda n: fn.fold[n]["h"]
        # stem: int8 input at S_in
        self.stem_b = self._bias(h("stem"), S0["in"] * g("stem"))
        self.stem_m = fixmul(S0["in"] * g("stem") / S0["s0"])
        self.blocks = []
        for i, e in enumerate(fn.blocks):
            p, si, so = f"blocks.{i}", S0[f"s{i}"], S0[f"s{i + 1}"]
            d = dict(fp=e["fp"], sc=e["sc"])
            if e["fp"]:
                sh, sm = S0[f"h{i}"], S0[f"m{i}"]
                d["hm"] = fixmul(torch.tensor([si / sh]))
                d["c1b"], d["c1m"] = self._bias(h(p + ".c1"), sh * g(p + ".c1")), fixmul(sh * g(p + ".c1") / sm)
                d["c2b"], d["c2m"] = self._bias(h(p + ".c2"), sm * g(p + ".c2")), fixmul(sm * g(p + ".c2") / so)
                if e["sc"]:
                    d["scb"], d["scm"] = self._bias(h(p + ".sc"), sh * g(p + ".sc")), fixmul(sh * g(p + ".sc") / so)
            else:
                assert torch.equal(e["sigma"], torch.sign(fn.fold[p + ".c1"]["g"])) and (e["sigma"] != 0).all()
                d["T1"] = torch.floor(e["t1"] / si)                             # b1 = 1[s_int > T1]
                assert d["T1"].abs().max() < 2 ** 40
                d["T1"] = d["T1"].long()
                d["T2"] = e["T"].long()                                          # b2 = 1[acc' >= T2], acc' = sign(g) M b1
                d["c2m"], d["c2h"] = fixmul(g(p + ".c2") / so), self._bias(h(p + ".c2"), so)
                if e["sc"]:
                    d["scm"], d["sch"] = fixmul(g(p + ".sc") / so), self._bias(h(p + ".sc"), so)
            if not e["sc"]:
                d["idm"] = fixmul(torch.tensor([si / so]))
            self.blocks.append(d)
        L = len(fn.blocks)
        self.sL = S0[f"s{L}"]
        self.pool_m = fixmul(torch.tensor([self.sL / (16 * S0["pool"])]))
        W = fn.fcw
        self.fsw = W.abs().amax(1) / 127
        self.fW8 = torch.round(W / self.fsw[:, None]).clamp(-127, 127).to(torch.int8)
        self.fbq = torch.round(fn.fcb / (S0["pool"] * self.fsw)).long()
        self.fscale = S0["pool"] * self.fsw

    @staticmethod
    def _bias(h, eff):
        b = torch.round(h / eff)
        assert b.abs().max() < I32, "bias overflows int32"
        return b.long()

    def acc(self, q, name):
        return self.ic[name].acc(q) - self.ic[name].bq[None, :, None, None]   # IntConv.acc adds its own (S_in=1) bias

    def clamp16(self, s):
        self.sat += int((s.abs() > Q16).sum())
        return s.clamp(-Q16, Q16)

    def __call__(self, x, trace=None):
        """x: uint8 NHWC.  trace: list -> appended (name, bits) of every 1-bit tensor."""
        x = data.prep(x, torch.float64)
        q = torch.round(x / self.S["in"]).clamp(-127, 127).long()
        a = self.acc(q, "stem") + self.stem_b[None, :, None, None]
        s = self.clamp16(requant(a, *self.stem_m))
        for i, d in enumerate(self.blocks):
            p = f"blocks.{i}"
            if d["fp"]:
                hq = requant(s.clamp(min=0), *d["hm"], 0, 127)
                z = requant(self.acc(hq, p + ".c1") + d["c1b"][None, :, None, None], *d["c1m"], 0, 127)
                r2 = requant(self.acc(z, p + ".c2") + d["c2b"][None, :, None, None], *d["c2m"])
                rs = requant(self.acc(hq, p + ".sc") + d["scb"][None, :, None, None], *d["scm"]) if d["sc"] else None
            else:
                hb = (s > d["T1"][None, :, None, None]).long()
                z = (self.acc(hb, p + ".c1") >= d["T2"][None, :, None, None]).long()
                if trace is not None:
                    trace += [(f"b{i}.b1", hb), (f"b{i}.b2", z)]
                r2 = requant(self.acc(z, p + ".c2"), *d["c2m"]) + d["c2h"][None, :, None, None]
                rs = requant(self.acc(hb, p + ".sc"), *d["scm"]) + d["sch"][None, :, None, None] if d["sc"] else None
            if rs is None:
                rs = requant(s.clamp(min=0), *d["idm"])
            s = self.clamp16(r2 + rs)
        assert s.shape[2:] == (4, 4)
        pq = requant(s.clamp(min=0).sum(dim=(2, 3)), *self.pool_m, 0, 127)
        return (igemm(F.linear, pq, self.fW8) + self.fbq).double() * self.fscale


def float_trace(fn, x, rec=None):
    """verify_bin.Folded forward (fp64, identical ops) recording calibration maxima (rec dict) and 1-bit tensors."""
    bits = []
    up = lambda k, t: rec.__setitem__(k, max(rec.get(k, 0.0), t.abs().max().item())) if rec is not None else None
    x = data.prep(x, torch.float64)
    up("in", x)
    s = fn.aff(fn.conv(x, "stem"), "stem")
    up("s0", s)
    for i, e in enumerate(fn.blocks):
        p = f"blocks.{i}"
        if e["fp"]:
            hin = F.relu(s)
            up(f"h{i}", hin)
            z = F.relu(fn.aff(fn.conv(hin, p + ".c1"), p + ".c1"))
            up(f"m{i}", z)
        else:
            hin = (s > e["t1"][:, None, None]).double()
            z = (e["sigma"][:, None, None] * fn.conv(hin, p + ".c1") >= e["T"][:, None, None]).double()
            bits += [(f"b{i}.b1", hin), (f"b{i}.b2", z)]
        r = fn.aff(fn.conv(hin, p + ".sc"), p + ".sc") if e["sc"] else F.relu(s)
        s = fn.aff(fn.conv(z, p + ".c2"), p + ".c2") + r
        up(f"s{i + 1}", s)
    pf = F.relu(s).mean((2, 3))
    up("pool", pf)
    return pf @ fn.fcw.T + fn.fcb, bits


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--calib", type=int, default=2000, help="first N images of the train split for calibration")
    ap.add_argument("--nbits", type=int, default=500, help="val images for the per-layer 1-bit disagreement")
    ap.add_argument("--test", action="store_true", help="evaluate the test set (once, at the end)")
    ap.add_argument("--force", action="store_true", help="allow --test although intbin.txt has a test result")
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    dev = "cuda"
    out_path = os.path.join(os.path.dirname(os.path.abspath(a.ckpt)), "intbin.txt")
    if a.test and not a.force and os.path.exists(out_path) and "test accuracy" in open(out_path).read():
        print(f"refusing: {out_path} already holds a test evaluation (--force to override)")
        return 1
    model, ck, o, logp, fpb = build(a.ckpt, dev)
    args = ck["args"]
    signed = args["mode"] == "signed"
    fn = Folded(model, fpb, signed, args["b"])
    lines = []
    log = lambda s: (print(s), lines.append(s))
    (xt, _), (xv, yv) = data.split(dev)
    rec = {}
    for i in range(0, a.calib, 500):
        lg, _ = float_trace(fn, xt[i:min(i + 500, a.calib)], rec)
    net = IntBin(model, fn, rec, signed)
    log(f"{a.ckpt}: mode {args['mode']}, b {args['b']}, epoch {ck['epoch']}, fp_blocks {list(fpb)}; integer-exact inference")
    log(f"calibration (folded fp64, train[:{a.calib}]): input int8 S {net.S['in']:.4g}; stream int16 S_k = max|s_k|/32767: "
        + " ".join(f"s{k}={net.S[f's{k}']:.3g}" for k in range(len(fn.blocks) + 1))
        + "".join(f"; fp-block {i} relu-in/mid int8 S {net.S[f'h{i}']:.3g}/{net.S[f'm{i}']:.3g}" for i in fpb)
        + f"; pool int8 S {net.S['pool']:.4g}")
    flips = sum(c.flips for c in net.ic.values())
    log(f"weights: {len(net.ic)} convs int sign(g) M in {{-1,0,1}}, QC re-proved (decompose + re-expand == M) PASS, "
        f"{flips} sign-flipped rows; FC int8 per-channel")
    zm = sum(int((d[k][0] == 0).sum()) for d in net.blocks for k in ("c1m", "c2m", "scm", "idm", "hm") if k in d)
    log(f"thresholds: b1 = 1[s_int > floor(t/S_k)], b2 = 1[sign(g) M b1 >= T] (verify_bin); "
        f"{zm} requant multipliers < 2^-32 set to 0")

    # val: folded fp64 vs integer
    n = len(yv)
    pf = torch.cat([fn(data.prep(xv[i:i + 500], torch.float64)).argmax(1) for i in range(0, n, 500)])
    net.sat = 0
    pi = torch.cat([net(xv[i:i + 500]).argmax(1) for i in range(0, n, 500)])
    cf, ci, diff = int((pf == yv).sum()), int((pi == yv).sum()), int((pf != pi).sum())
    log(f"val: folded fp64 {100 * cf / n:.2f} % ({cf}/{n}), integer {100 * ci / n:.2f} % ({ci}/{n}), "
        f"argmax differs on {diff} images; int16 stream saturations {net.sat}")

    # per-layer 1-bit disagreement on the first nbits val images
    xb = xv[:a.nbits]
    lgf, bf = float_trace(fn, xb)
    assert torch.equal(lgf, fn(data.prep(xb, torch.float64))), "float_trace != Folded"
    bi = []
    net(xb, bi)
    log(f"1-bit activations differing integer vs folded fp64 (end-to-end, val[:{a.nbits}]):")
    worst = (0.0, "")
    for (nf, tf), (ni, ti) in zip(bf, bi):
        assert nf == ni
        fr = (tf.long() != ti).double().mean().item()
        worst = max(worst, (fr, nf))
        log(f"  {nf:8s} {tuple(tf.shape[1:])}  {fr:.3e}  ({int((tf.long() != ti).sum())} / {tf.numel()})")
    log(f"  worst: {worst[1]} {worst[0]:.3e}")
    if a.test:
        xs, ys = data.test(dev)
        net.sat = 0
        c = sum(int((net(xs[i:i + 500]).argmax(1) == ys[i:i + 500]).sum()) for i in range(0, len(ys), 500))
        log(f"test accuracy: integer {100 * c / len(ys):.2f} % ({c}/{len(ys)}); int16 stream saturations {net.sat}")
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
