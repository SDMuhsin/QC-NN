"""Verify that a qc18.train checkpoint is a QC network:  python3 -m qc18.verify CKPT [--test]

For every conv (stem, block convs, shortcuts): take the weight the model actually uses in eval mode, fold BN
into a per-output-channel scale s_c and bias, recover M = W_folded / s_c (exact: entries are 0/+-1), and prove
the full matrix (incl. the zero-padded input-channel columns of the stem) is QC with qc.structure.decompose.
Then evaluate the FOLDED network (conv with the exact integer M, then explicit * s_c + bias) in fp64 on val
(and test with --test), and require it to match the model's own fp32 eval within --tol images.  Exit 1 on failure.
"""
import argparse
import copy
import sys

import torch
import torch.nn as nn
import torch.nn.functional as F

from qc.structure import decompose, expand, from_matrix, to_matrix

from .data import prep, split, test
from .model import QCResNet18
from .qcconv import hard, row_alpha
from .train import accuracy


def fold(bn):
    s = bn.weight / torch.sqrt(bn.running_var + bn.eps)
    return s, bn.bias - bn.running_mean * s


class FoldedConv(nn.Module):
    """conv(x, M) * s + bias with the exact integer matrix M (BN folded)."""

    def __init__(self, conv, M, s, bias):
        super().__init__()
        self.stride, self.padding = conv.stride, conv.padding
        self.register_buffer("W", from_matrix(M, conv.cin, conv.k, conv.b))
        self.register_buffer("s", s)
        self.register_buffer("bias", bias)

    def forward(self, x):
        y = F.conv2d(x, self.W.to(x.dtype), stride=self.stride, padding=self.padding)
        return y * self.s.to(x.dtype)[:, None, None] + self.bias.to(x.dtype)[:, None, None]


def load(path, dev):
    ck = torch.load(path, map_location=dev)
    a = ck["args"]
    model = QCResNet18(a["mode"], a["b"], a["estimator"], a["tau0"]).to(dev)
    model.load_state_dict(ck["state"])
    return ck, model.eval()


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--test", action="store_true", help="also evaluate the test set")
    ap.add_argument("--tol", type=int, default=2, help="max |folded - model| correct images")
    a = ap.parse_args()
    torch.backends.cudnn.allow_tf32 = torch.backends.cuda.matmul.allow_tf32 = False
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    ck, model = load(a.ckpt, dev)
    args = ck["args"]
    if args["mode"] == "dense":
        print("FAIL: dense checkpoint (no QC structure)")
        return 1
    if args.get("relax", "none") != "none":
        print(f"FAIL: relax={args['relax']} checkpoint (diagnostic, real weights, not QC)")
        return 1
    signed, b = args["mode"] == "signed", args["b"]
    print(f"{a.ckpt}: mode {args['mode']}, b {b}, estimator {args['estimator']}, epoch {ck['epoch']}")
    print(f"{'layer':16s} {'matrix':>12s} {'density':>8s} {'zero':>6s} {'1sh':>6s} {'2sh':>6s} {'theta!=v':>8s}  result")
    ok, folded = True, copy.deepcopy(model).double()
    fmods = dict(folded.convbns())
    for name, cb in model.convbns():
        conv = cb.conv
        try:
            W = conv.get_weight().double()                          # what the model uses (eval: stored v)
            s, bias = (t.double() for t in fold(cb.bn))
            assert torch.isfinite(s).all() and (s != 0).all(), "BN scale zero / not finite"
            Wf = s[:, None, None, None] * W                         # folded weight
            Mfull = conv.matrix().double()                          # incl. padded input-channel columns
            C = decompose(Mfull, b, signed=signed)
            assert torch.equal(expand(torch.as_tensor(C, dtype=torch.float64, device=dev), b), Mfull), "re-expansion"
            assert torch.equal(from_matrix(Mfull, conv.cin, conv.k, b), W), "model weight != QC matrix"
            Mrec = to_matrix(Wf / s[:, None, None, None], b)         # padded columns are zero here
            real = to_matrix(torch.ones_like(W), b) != 0
            assert torch.equal(Mrec[real], Mfull[real]) and (Mrec[~real] == 0).all(), "W_folded / s != M"
            nb = torch.as_tensor((C != 0).sum(-1)).flatten()
            redo = (hard(conv.theta, row_alpha(conv.theta), signed) != conv.v).any(-1).double().mean().item()
            res = f"PASS  |s|min {s.abs().min():.2g}"
            fm = fmods[name]
            fm.conv, fm.bn = FoldedConv(conv, Mfull, s, bias), nn.Identity()
        except (ValueError, AssertionError) as e:
            ok, res, nb, redo = False, f"FAIL  {e}", torch.full((1,), -1), float("nan")
            Mfull = conv.matrix()
        print(f"{name:16s} {str(tuple(Mfull.shape)):>12s} {(Mfull != 0).double().mean():8.4f} "
              f"{(nb == 0).double().mean():6.3f} {(nb == 1).double().mean():6.3f} {(nb == 2).double().mean():6.3f} "
              f"{redo:8.1e}  {res}")
    folded.eval()
    sets = [("val", split(dev)[1])] + ([("test", test(dev))] if a.test else [])
    for nm, (x, y) in sets:
        n = len(y)
        # folded network in fp64 (prep in fp64), model in fp32 as in training eval
        cf = sum((folded(prep(x[i:i + 500], torch.float64)).argmax(1) == y[i:i + 500]).sum().item() for i in range(0, n, 500))
        cm = round(accuracy(model, x, y) * n)
        good = abs(cf - cm) <= a.tol
        ok &= good
        extra = f", checkpoint {100 * ck['val']:.2f} %" if nm == "val" else ""
        print(f"{nm} accuracy: folded QC network (fp64) {100 * cf / n:.2f} %, model (fp32) {100 * cm / n:.2f} %{extra}"
              f"  [{cf - cm:+d} images] {'PASS' if good else 'FAIL'}")
    print("VERIFY", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
