"""Verify a binary-activation qc18b checkpoint (qc18b.train_bin, preact=1, arch qc18) as a QC network with folded BN and
folded BinAct thresholds:   CUDA_VISIBLE_DEVICES=0 python3 -m qc18b.verify_bin CKPT [--test]

1. Rebuild the model exactly as trained (checkpoint args + the train.log / log.txt line starting 'binact=', incl. fp_blocks);
   val accuracy in fp32 (eval mode, cudnn defaults as in training, i.e. cudnn TF32 on; and with TF32 off) vs the saved val.
2. Fold every conv (stem, c1, c2, sc; 20 convs): exact integer QC matrix M (decompose, signed, b, <= 2 shifts per block,
   re-expanded == M, == the weight the model uses) and BN -> y = g * (M x) + h, g = gamma / sqrt(var + eps), h = beta - mean g.
   b2 = 1[g acc + h > t] with acc = M b1 (integer, exact in fp64) is folded to an integer-accumulator comparison:
     sigma = sign(g), tau = (t - h) / |g|, T = floor(tau) + 1:  b2 = 1[sigma * acc >= T]  (== 1[sigma * acc > tau], acc integer)
     g < 0: sigma = -1 (the comparison flips);  g = 0: sigma = 0, b2 is the constant 1[h > t], encoded T = 0 (always 1) or 1 (never).
   b1 reads the multi-bit pre-ReLU stream s = g2 acc2 + h2 + residual: kept as the float compare 1[s > t].
   --fp-blocks blocks: b1 / b2 = ReLU on the folded float tensors.
3. Folded network in fp64 (integer conv, explicit affine, integer/float compares) on val (+ test with --test) vs the trained
   model's own fp64 forward: argmax differences and accuracies.  Exit 1 if a QC proof fails or > 0.1 % of images differ.
4. Summary: per-conv input activation bit-width and the multi-bit tensors of the network.
"""
import argparse
import math
import os
import sys

import torch
import torch.nn.functional as F

from qc.structure import decompose, expand, from_matrix
from qc18.model import QCResNet18

from . import binact, data


def read_opts(ckpt):
    d = os.path.dirname(ckpt)
    for name in ("train.log", "log.txt"):
        p = os.path.join(d, name)
        if os.path.exists(p):
            with open(p) as f:
                line = next((ln for ln in f if ln.startswith("binact=")), None)
            if line:
                return dict(kv.split("=", 1) for kv in line.split()), p
    raise FileNotFoundError(f"no 'binact=' line in {d}/train.log or log.txt")


def build(ckpt, dev):
    """as qc18b.diag.diagnose.build_bin (checkpoint args + 'binact=' log line), plus fp_blocks."""
    o, logp = read_opts(ckpt)
    assert o["arch"] == "qc18" and o["preact"] == "1" and o["stem_therm"] == "0" and o["bin_stem"] == "0", o
    assert o["binact"] == "1" and not o.get("abits_blocks") and not o.get("xfb_blocks"), o
    ck = torch.load(ckpt, map_location=dev, weights_only=False)
    a = ck["args"]
    m = QCResNet18(a["mode"], a["b"], a["estimator"], a["tau0"], num_classes=data.NUM_CLASSES, relax=a["relax"],
                   qinit_scale=a["qinit_scale"], homotopy=a["homotopy"]).to(dev).to(memory_format=torch.channels_last)
    fpb = tuple(int(i) for i in o["fp_blocks"].split(",") if i)
    m = binact.binarize(m, o["ste"], float(o["w"]), 0, "", 0, 1, False, act=True, k=float(o["K"]), t_train=int(o["t_train"]),
                        preact=1, arch="qc18", fp_blocks=fpb)
    m.load_state_dict(ck["state"])          # strict
    if a["homotopy"] != "none":
        m.set_homotopy(False)
    return m.eval(), ck, o, logp, fpb


@torch.no_grad()
def fold_conv(cb, signed, b):
    """-> dict(W integer weight fp64, g, h, stride, padding, C); raises AssertionError / ValueError on failure."""
    conv, bn = cb.conv, cb.bn
    assert conv.mode != "dense" and conv.relax == "none" and not conv.training
    Mfull = conv.matrix().double()                                   # incl. zero-padded input-channel columns
    assert torch.equal(Mfull, Mfull.round()), "M not integer"
    C = decompose(Mfull, b, signed=signed)                           # QC proof (ValueError if not)
    assert torch.equal(expand(torch.as_tensor(C, dtype=torch.float64, device=Mfull.device), b), Mfull), "re-expansion"
    W = conv.get_weight().double()                                   # what the model uses (eval: stored v)
    assert torch.equal(from_matrix(Mfull, conv.cin, conv.k, b), W), "model weight != QC matrix"
    g = bn.weight.double() / torch.sqrt(bn.running_var.double() + bn.eps)
    h = bn.bias.double() - bn.running_mean.double() * g
    assert torch.isfinite(g).all() and torch.isfinite(h).all()
    nb = torch.as_tensor((C != 0).sum(-1)).flatten()
    return dict(W=W, g=g, h=h, stride=conv.stride, padding=conv.padding, C=C, shape=tuple(Mfull.shape),
                density=(Mfull != 0).double().mean().item(), nb=nb)


def fold_b2(c1, t):
    """b2 = 1[g acc + h > t] -> 1[sigma acc >= T] (acc integer).  Returns sigma, T, stats."""
    g, h, t = c1["g"], c1["h"], t.double()
    sigma = torch.sign(g)
    nz = g != 0
    tau = torch.where(nz, (t - h) / g.abs().clamp_min(1e-300), torch.zeros_like(g))
    T = torch.where(nz, torch.floor(tau) + 1, torch.where(h > t, torch.zeros_like(g), torch.ones_like(g)))
    Mabs = c1["W"].flatten(1)                                        # reachable acc range for b1 in {0,1}
    lo, hi = sigma * torch.where(sigma >= 0, Mabs.clamp(max=0).sum(1), Mabs.clamp(min=0).sum(1)), \
        sigma * torch.where(sigma >= 0, Mabs.clamp(min=0).sum(1), Mabs.clamp(max=0).sum(1))
    const = int(((T <= lo) | (T > hi) | ~nz).sum())                  # b2 constant for every input
    frac = (tau - torch.round(tau)).abs()[nz]                       # distance of tau to the nearest integer
    return sigma, T, dict(const=const, neg=int((g < 0).sum()), zero=int((~nz).sum()), n=g.numel(),
                          min_int_dist=frac.min().item() if frac.numel() else float("nan"),
                          T_min=T[nz].min().item() if nz.any() else float("nan"),
                          T_max=T[nz].max().item() if nz.any() else float("nan"))


class Folded:
    """Folded fp64 network: integer convs, explicit per-channel affine, integer b2 compare, float b1 compare."""

    def __init__(self, model, fpb, signed, b):
        self.fold, self.fpb, self.blocks = {}, fpb, []
        self.fold["stem"] = fold_conv(model.stem, signed, b)
        for i, blk in enumerate(model.blocks):
            e = dict(fp=i in fpb, sc=blk.sc is not None)
            for c in ("c1", "c2", "sc"):
                if getattr(blk, c) is not None:
                    self.fold[f"blocks.{i}.{c}"] = fold_conv(getattr(blk, c), signed, b)
            if not e["fp"]:
                e["t1"] = blk.b1.t.detach().double()
                e["sigma"], e["T"], e["b2stats"] = fold_b2(self.fold[f"blocks.{i}.c1"], blk.b2.t.detach())
                e["t2"] = blk.b2.t.detach().double()
            self.blocks.append(e)
        self.fcw, self.fcb = model.fc.weight.double(), model.fc.bias.double()
        self.mismatch = 0            # b2 elements where integer compare != float compare 1[g acc + h > t] (diagnostic)
        self.nonint = 0              # binary-input accumulators that are not integers (must stay 0)

    def conv(self, x, name):
        f = self.fold[name]
        return F.conv2d(x, f["W"], stride=f["stride"], padding=f["padding"])

    def aff(self, acc, name):
        f = self.fold[name]
        return f["g"][:, None, None] * acc + f["h"][:, None, None]

    def __call__(self, x):
        s = self.aff(self.conv(x, "stem"), "stem")                   # stem: 8-bit image (normalised), multi-bit s0
        for i, e in enumerate(self.blocks):
            p = f"blocks.{i}"
            if e["fp"]:
                hin = F.relu(s)
                z = F.relu(self.aff(self.conv(hin, p + ".c1"), p + ".c1"))
            else:
                hin = (s > e["t1"][:, None, None]).double()           # b1: float compare on the multi-bit stream
                acc = self.conv(hin, p + ".c1")
                self.nonint += int((acc != acc.round()).sum())
                z = (e["sigma"][:, None, None] * acc >= e["T"][:, None, None]).double()   # b2: integer compare
                zf = (self.aff(acc, p + ".c1") > e["t2"][:, None, None]).double()
                self.mismatch += int((z != zf).sum())
            acc2 = self.conv(z, p + ".c2")
            if not e["fp"]:
                self.nonint += int((acc2 != acc2.round()).sum())
            r = self.aff(self.conv(hin, p + ".sc"), p + ".sc") if e["sc"] else F.relu(s)
            s = self.aff(acc2, p + ".c2") + r
        return F.relu(s).mean((2, 3)) @ self.fcw.T + self.fcb


def preds(f, x, dtype, bs=500):
    return torch.cat([f(data.prep(x[i:i + bs], dtype)).argmax(1) for i in range(0, len(x), bs)])


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--test", action="store_true", help="also evaluate the test set (once per final checkpoint)")
    a = ap.parse_args()
    dev = "cuda"
    model, ck, o, logp, fpb = build(a.ckpt, dev)
    args = ck["args"]
    signed, b = args["mode"] == "signed", args["b"]
    print(f"{a.ckpt}: mode {args['mode']}, b {b}, epoch {ck['epoch']}, saved val {100 * ck['val']:.2f} %")
    print(f"binact options ({logp}): " + " ".join(f"{k}={v}" for k, v in o.items()))
    (_, _), (xv, yv) = data.split(dev)
    nv = len(yv)

    # 1. fp32 val, TF32 off (reproduces the saved val) and with cudnn TF32 on (sensitivity only)
    ok = True
    saved = round(ck["val"] * nv)
    for tf32 in (False, True):
        torch.backends.cudnn.allow_tf32 = tf32
        c = int((preds(model, xv, torch.float32) == yv).sum())
        print(f"[1] model fp32 val (cudnn tf32={tf32}): {100 * c / nv:.2f} % ({c}/{nv}), saved {saved}/{nv}: "
              f"{c - saved:+d} images")
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False

    # 2. fold + QC proof
    print(f"[2] fold: {'layer':16s} {'matrix':>12s} {'density':>8s} {'zero':>6s} {'1sh':>6s} {'2sh':>6s} {'in-act':>8s}  result")
    try:
        fn = Folded(model, fpb, signed, b)
        qc_ok = True
    except (ValueError, AssertionError) as e:
        print(f"QC proof FAIL: {e}")
        print("VERIFY FAIL")
        return 1
    inact = {"stem": "8b-img"}
    for i in range(len(model.blocks)):
        for c in ("c1", "c2", "sc"):
            inact[f"blocks.{i}.{c}"] = "FP" if i in fpb else "1"
    for name, f in fn.fold.items():
        nb = f["nb"]
        print(f"    {name:16s} {str(f['shape']):>12s} {f['density']:8.4f} {(nb == 0).double().mean():6.3f} "
              f"{(nb == 1).double().mean():6.3f} {(nb == 2).double().mean():6.3f} {inact[name]:>8s}  PASS "
              f"|g| min {f['g'].abs().min():.2g} g<0 {int((f['g'] < 0).sum())}")
    print(f"    QC proof: {len(fn.fold)} convs PASS (signed={signed}, b={b}, <= 2 shifts per block, re-expanded, == model weight)")
    print("    b2 fold per block (c1 BN + BinAct t -> 1[sign(g) acc >= T], acc = integer M b1):")
    for i, e in enumerate(fn.blocks):
        if e["fp"]:
            print(f"      block {i}: fp-block (b1 = b2 = ReLU, float)")
        else:
            s = e["b2stats"]
            print(f"      block {i}: {s['n']} ch, g<0 {s['neg']}, g=0 {s['zero']}, constant-output ch {s['const']}, T in [{s['T_min']:.0f}, {s['T_max']:.0f}], "
                  f"min |tau - round(tau)| {s['min_int_dist']:.3g}")

    # 3. folded fp64 vs model fp64
    md = model.double()
    sets = [("val", xv, yv)] + ([("test",) + data.test(dev)] if a.test else [])
    for nm, x, y in sets:
        n = len(y)
        pm = preds(md, x, torch.float64)
        pf = preds(fn, x, torch.float64)
        diff = int((pm != pf).sum())
        cm, cf = int((pm == y).sum()), int((pf == y).sum())
        good = diff <= 0.001 * n
        ok &= good
        print(f"[3] {nm}: model fp64 {100 * cm / n:.2f} % ({cm}/{n}), folded fp64 {100 * cf / n:.2f} % ({cf}/{n}), "
              f"argmax differs on {diff} images ({100 * diff / n:.3f} %) {'PASS' if good else 'FAIL'}")
        p32 = preds(model.float(), x, torch.float32)                 # fp32 model (TF32 off), reference only
        model.double()
        c32 = int((p32 == y).sum())
        print(f"    {nm}: model fp32 {100 * c32 / n:.2f} % ({c32}/{n}); model fp32 vs fp64 argmax differs on "
              f"{int((p32 != pm).sum())} images ({c32 - cm:+d} correct)")
    print(f"    b2 elements integer compare != float compare 1[g acc + h > t]: {fn.mismatch}; "
          f"non-integer binary-input accumulators: {fn.nonint}")
    ok &= fn.nonint == 0

    # 4. summary
    print("[4] per-conv input activation: stem 8-bit image (normalised (x/255 - mean)/std, float); "
          + "; ".join(f"block {i} c1/sc/c2 {'FP (fp-block, ReLU)' if i in fpb else '1-bit'}" for i in range(len(model.blocks))))
    mb = ["stem input image (8-bit, normalised float)", "stem BN output s0 (pre-ReLU stream)",
          "residual stream s_k = block outputs (pre-ReLU, read by b1 float compare)",
          "c2 BN outputs g2*acc2 + h2 (added into the stream)", "sc BN outputs (downsampling blocks 2, 4, 6)",
          "identity shortcut relu(s) (non-downsampling blocks)",
          "integer accumulators acc = M b (c1, c2, sc; c1 acc compared to integer T for b2)"]
    if fpb:
        mb.append(f"fp-block {','.join(map(str, fpb))} activations: relu(s) (c1/sc input), c1 BN output, relu(c1 BN) (c2 input)")
    mb.append("pool/FC input relu(s_7) and its global average (512-d)")
    print("    multi-bit tensors: " + " | ".join(mb))
    print("VERIFY", "PASS" if ok and qc_ok else "FAIL")
    return 0 if ok and qc_ok else 1


if __name__ == "__main__":
    sys.exit(main())
