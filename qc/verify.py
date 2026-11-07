"""Verify that a trained checkpoint is a QC network:  python -m qc.verify CKPT

Per conv: extract the exact coefficient matrix (0/1 or -1/0/1, incl. padded input-channel columns),
prove every b x b block is QC with structure.decompose, check that the conv weight the model uses is
exactly that matrix, and fold BN into a per-channel scale + bias.  Then re-evaluates the val split
with the folded network (integer-valued conv matrix, conv -> scale -> bias) against the checkpoint.
Exits 1 if any layer fails.
"""
import sys

import torch
import torch.nn.functional as F

from nn.model.resnet8 import CONVS, keras_same_pad

from .model import QCResNet8
from .structure import decompose, expand, from_matrix
from .train import split


def fold(bn):
    scale = bn.weight / torch.sqrt(bn.running_var + bn.eps)
    return scale, bn.bias - bn.running_mean * scale


@torch.no_grad()
def folded_forward(model, mats, x):
    def c(n, h):
        conv = model.conv[n]
        W = from_matrix(mats[n], conv.cin, conv.k, conv.b, conv.view)
        scale, bias = fold(model.bn[n])
        y = F.conv2d(keras_same_pad(h, conv.k, conv.stride), W, stride=conv.stride)
        y = y * scale[:, None, None] + bias[:, None, None]
        return F.relu(y) if model.relu[n] else y
    x = x.permute(0, 3, 1, 2).double()
    x0 = c("conv0", x)
    x1 = F.relu(x0 + c("conv2", c("conv1", x0)))
    x2 = F.relu(c("conv5", x1) + c("conv4", c("conv3", x1)))
    x3 = F.relu(c("conv8", x2) + c("conv7", c("conv6", x2)))
    return model.fc(x3.mean(dim=(2, 3)))


def load(ck):
    """Checkpoint dict -> fp64 CPU model in eval mode."""
    a = ck["args"]
    model = QCResNet8(a["mode"], a["b"], a["topk"], a["view"], a.get("method", "ste"), a.get("thr", 0.0)).double()
    model.load_state_dict({k: v.cpu() for k, v in ck["state"].items()})
    return model.eval()


@torch.no_grad()
def folded_accuracy(model, x, y, bs=1000):
    """Accuracy of the exact folded QC network (integer conv matrices, conv -> scale -> bias), fp64."""
    mats = {n: model.conv[n].matrix() for n in model.conv}
    x, y = x.cpu(), y.cpu()
    c = sum((folded_forward(model, mats, x[i:i + bs].double()).argmax(1) == y[i:i + bs]).sum().item()
            for i in range(0, len(x), bs))
    return c / len(x)


@torch.no_grad()
def main(path):
    ck = torch.load(path, map_location="cpu")
    a = ck["args"]
    model = load(ck)
    if a["mode"] == "dense":
        print("FAIL: dense checkpoint (no QC structure)")
        return 1
    ok, mats = True, {}
    print(f"{path}: mode {a['mode']}, top-{a['topk']}, view {a['view']}")
    print(f"{'layer':6s} {'b':>3s} {'matrix':>10s} {'density':>8s} {'zero blk':>8s} {'1 shift':>7s} {'2 shift':>7s}  result")
    for n, *_ in CONVS:
        conv = model.conv[n]
        M = conv.matrix()
        mats[n] = M
        try:
            C = decompose(M, conv.b, signed=a["mode"] == "signed")
            assert torch.equal(expand(torch.as_tensor(C, dtype=M.dtype), conv.b), M), "re-expansion differs"
            assert torch.equal(from_matrix(M, conv.cin, conv.k, conv.b, conv.view), conv.weight_eff()), \
                "model weight != QC matrix"
            scale, _ = fold(model.bn[n])
            assert torch.isfinite(scale).all()
            nb = (C != 0).sum(-1)
            res = f"PASS  (BN scale |min| {scale.abs().min():.3g})"
        except (ValueError, AssertionError) as e:
            ok, res, nb = False, f"FAIL  {e}", torch.full((1,), -1)
        nb = torch.as_tensor(nb).flatten()
        print(f"{n:6s} {conv.b:3d} {str(tuple(M.shape)):>10s} {(M != 0).double().mean():8.4f} "
              f"{(nb == 0).double().mean():8.3f} {(nb == 1).double().mean():7.3f} {(nb == 2).double().mean():7.3f}  {res}")
    _, (xv, yv) = split("cpu")
    acc_f = (folded_forward(model, mats, xv.double()).argmax(1) == yv).double().mean().item()
    acc_m = (model(xv.double()).argmax(1) == yv).double().mean().item()
    print(f"val accuracy: folded QC network {100 * acc_f:.2f} %, model {100 * acc_m:.2f} %, "
          f"checkpoint {100 * ck['val']:.2f} % (training precision)")
    ok &= abs(acc_f - acc_m) < 1e-9
    print("VERIFY", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
