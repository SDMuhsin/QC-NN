"""Post-training int8 quantization of ResNet-8 for GeMMX, and the integer-only reference model.

Scheme (chosen so that every conv is ONE GeMMX call with the SIMD stage doing requant + ReLU):
  * activations: per-tensor int8.  ReLU outputs use zero point -128 (full 8 bit for x >= 0,
    ReLU = the int8 lower clamp); conv outputs that feed a residual add are symmetric (zp 0).
    The network input is the raw pixel minus 128 (scale 1, zp -128): lossless.
  * conv weights: symmetric int8, one scale per SIMD lane (lane = out channel % 8; the 8
    lanes of the RescaleSIMD have their own multiplier/shift) or per tensor (--wgran tensor).
  * conv bias: int32 in the GeMMX C input (broadcast per channel), + rounding offset
    2^(s-1)/m so that the SIMD floor-shift rounds to nearest.
  * input zero point -> GeMMX subtraction_a (padding is filled with the zero point);
    SIMD input_zp = 0, output_zp = zp_out, clamp [-128, 127].
  * residual add + requant, global avgpool (sum), FC (int32 logits): Snitch cores.

The integer reference (IntResNet8) is plain PyTorch on int64 tensors (convs are evaluated in
float64, exact because every partial sum is an integer < 2^53) and uses nn.quant.hw for the
requant arithmetic.

    python -m nn.quant.quantize [--wgran lane|tensor] [--calib N] [--pct P]
        -> nn/build/qparams.pt, prints float and int8 accuracy on the full test set
"""
import argparse
import os

import numpy as np
import torch
import torch.nn.functional as F

from ..model.data import H5_PATH, test_set, train_set
from ..model.resnet8 import CONV_CFG, CONVS, ResNet8, evaluate, keras_same_pad, load_h5
from .hw import ADD_SHIFT, core_add_requant, quantize_multiplier, simd_rescale

BUILD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build")
LANES = 8

# conv name -> input tensor name;  add name -> (a, b) inputs
CONV_IN = {"conv0": "input", "conv1": "conv0", "conv2": "conv1", "conv3": "add1", "conv4": "conv3",
           "conv5": "add1", "conv6": "add2", "conv7": "conv6", "conv8": "add2"}
ADDS = {"add1": ("conv0", "conv2"), "add2": ("conv5", "conv4"), "add3": ("conv8", "conv7")}
RELU_T = {"conv0", "conv1", "conv3", "conv6", "add1", "add2", "add3"}  # zp = -128 tensors


def calibrate(model, x, pct):
    """Per-tensor ranges from float taps on calibration images."""
    taps = {}
    with torch.no_grad():
        for i in range(0, len(x), 500):
            t = {}
            model.forward(x[i:i + 500], t)
            for k, v in t.items():
                taps.setdefault(k, []).append(v.flatten().abs().cpu())
    rng = {}
    for k, v in taps.items():
        v = torch.cat(v)
        rng[k] = float(torch.quantile(v[torch.randperm(len(v))[:2_000_000]].double(), pct / 100)) if pct < 100 \
            else float(v.max())
    return rng


def build_qparams(params, rng, wgran="lane"):
    """Float params + activation ranges -> integer parameters of every layer."""
    act = {"input": (1.0, -128)}
    for k, r in rng.items():
        if k in ("pool", "fc"):
            continue
        act[k] = (r / 255.0, -128) if k in RELU_T else (r / 127.0, 0)
    q = {"act": act, "conv": {}, "add": {}}
    for name, *_ in CONVS:
        W, b = params[name]
        cout = W.shape[0]
        s_in, z_in = act[CONV_IN[name]]
        s_out, z_out = act[name]
        wmax = np.abs(W).reshape(cout, -1).max(1)
        if wgran == "lane":
            lane_max = np.array([wmax[l::LANES].max() for l in range(min(LANES, cout))])
            sw = np.array([lane_max[c % LANES] for c in range(cout)]) / 127.0
        else:
            sw = np.full(cout, wmax.max() / 127.0)
        Wq = np.clip(np.round(W / sw[:, None, None, None]), -127, 127).astype(np.int64)
        ms = [quantize_multiplier(s_in * sw[l] / s_out) for l in range(LANES)]  # lane l (cout >= 8)
        mult = np.array([ms[c % LANES][0] for c in range(cout)], dtype=np.int64)
        shift = np.array([ms[c % LANES][1] for c in range(cout)], dtype=np.int64)
        rnd = np.round(2.0 ** (shift - 1) / mult).astype(np.int64)
        bq = np.round(b / (s_in * sw)).astype(np.int64) + rnd
        assert np.all(np.abs(bq) < 2 ** 30)
        q["conv"][name] = dict(W=Wq, bias=bq, mult=mult, shift=shift, zp_in=z_in, zp_out=z_out,
                               lo=-128, hi=127, sw=sw)
    for name, (a, b) in ADDS.items():
        (sa, za), (sb, zb), (so, zo) = act[a], act[b], act[name]
        ma, mb = round(sa / so * 2 ** ADD_SHIFT), round(sb / so * 2 ** ADD_SHIFT)
        # int32 safety of t = (a-za)*ma + (b-zb)*mb + 2^(s-1) on the cores
        assert 255 * (ma + mb) + 2 ** ADD_SHIFT < 2 ** 31
        # folded form used in C: a*ma + b*mb + (2^15 + zo*2^16 - za*ma - zb*mb)
        kc = 2 ** (ADD_SHIFT - 1) + zo * 2 ** ADD_SHIFT - za * ma - zb * mb
        assert 128 * (ma + mb) + abs(kc) < 2 ** 31
        q["add"][name] = dict(a=a, b=b, za=za, ma=ma, zb=zb, mb=mb, zo=zo, lo=-128)
    W, b = params["fc"]
    s3, z3 = act["add3"]
    sw = np.abs(W).max() / 127.0
    q["fc"] = dict(W=np.clip(np.round(W / sw), -127, 127).astype(np.int64),
                   bias=np.round(b * 64 / (s3 * sw)).astype(np.int64), zp_in=z3, pool=64)
    return q


class IntResNet8:
    """Integer-only reference: int8 activations, int32 accumulators, GeMMX / core arithmetic."""

    def __init__(self, q, device="cpu"):
        self.q, self.dev = q, device
        self.w = {k: torch.tensor(v["W"], dtype=torch.float64, device=device) for k, v in q["conv"].items()}
        self.cp = {}
        for k, v in q["conv"].items():
            c = lambda a: torch.tensor(a, dtype=torch.int64, device=device).view(1, -1, 1, 1)
            self.cp[k] = (c(v["bias"]), c(v["mult"]), c(v["shift"]))

    def quant_input(self, x_u8):
        x = torch.as_tensor(np.asarray(x_u8), device=self.dev).to(torch.int64).permute(0, 3, 1, 2)
        return x - 128

    def conv(self, name, x):
        """One GeMMX call: int8 x (NCHW int64) -> int8 output."""
        v = self.q["conv"][name]
        _, _, k, s, _, _, _ = CONV_CFG[name][1:]
        xin = keras_same_pad((x - v["zp_in"]).double(), k, s)        # padding holds the zero point
        acc = F.conv2d(xin, self.w[name], stride=s).round().to(torch.int64)
        bias, mult, shift = self.cp[name]
        acc = acc + bias
        acc = ((acc + 2 ** 31) % 2 ** 32) - 2 ** 31                  # int32 accumulator
        return simd_rescale(acc, 0, v["zp_out"], mult, shift, v["lo"], v["hi"])

    def add(self, name, ta, tb):
        v = self.q["add"][name]
        return core_add_requant(ta, v["za"], v["ma"], tb, v["zb"], v["mb"], v["zo"], v["lo"])

    def forward(self, x_u8, taps=None):
        t = taps if taps is not None else {}
        t["input"] = x = self.quant_input(x_u8)
        t["conv0"] = x0 = self.conv("conv0", x)
        t["conv1"] = h = self.conv("conv1", x0)
        t["conv2"] = y = self.conv("conv2", h)
        t["add1"] = x1 = self.add("add1", x0, y)
        t["conv3"] = h = self.conv("conv3", x1)
        t["conv4"] = y = self.conv("conv4", h)
        t["conv5"] = sc = self.conv("conv5", x1)
        t["add2"] = x2 = self.add("add2", sc, y)
        t["conv6"] = h = self.conv("conv6", x2)
        t["conv7"] = y = self.conv("conv7", h)
        t["conv8"] = sc = self.conv("conv8", x2)
        t["add3"] = x3 = self.add("add3", sc, y)
        fc = self.q["fc"]
        t["pool"] = p = (x3 - fc["zp_in"]).sum(dim=(2, 3))            # int32 channel sums
        W = torch.tensor(fc["W"], dtype=torch.int64, device=self.dev)
        t["fc"] = logits = p @ W.T + torch.tensor(fc["bias"], dtype=torch.int64, device=self.dev)
        return logits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wgran", choices=["lane", "tensor"], default="lane")
    ap.add_argument("--calib", type=int, default=2000, help="calibration images (training set)")
    ap.add_argument("--pct", type=float, default=99.99, help="activation range percentile (100 = max)")
    ap.add_argument("--out", default=os.path.join(BUILD, "qparams.pt"))
    a = ap.parse_args()
    torch.manual_seed(0)
    params = load_h5(H5_PATH)
    fm = ResNet8(params)
    xt, yt = test_set()
    xtr, _ = train_set()
    calib = xtr[np.random.default_rng(0).permutation(len(xtr))[:a.calib]]
    q = build_qparams(params, calibrate(fm, calib, a.pct), a.wgran)
    im = IntResNet8(q)
    acc_f = evaluate(fm.forward, xt, yt)
    acc_q = evaluate(im.forward, xt, yt)
    print(f"float {100 * acc_f:.2f} %   int8 ({a.wgran} weights, calib {a.calib} @ p{a.pct}) "
          f"{100 * acc_q:.2f} %   (CIFAR-10 test, 10000 images)")
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    q["meta"] = dict(acc_float=acc_f, acc_int8=acc_q, wgran=a.wgran, calib=a.calib, pct=a.pct)
    torch.save(q, a.out)
    print("wrote", a.out)


if __name__ == "__main__":
    main()
