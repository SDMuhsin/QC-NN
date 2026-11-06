"""MLPerf Tiny ResNet-8 (CIFAR-10) in PyTorch, loaded from the Keras pretrainedResnet.h5.

Graph (mlcommons/tiny benchmark/training/image_classification/keras_model.py, 16 filters):
    conv0 3x3 (3->16) BN ReLU                                      -> x0
    stack1: conv1 3x3 BN ReLU, conv2 3x3 BN; add(x0, .) ReLU        -> x1   (16 ch, 32x32)
    stack2: conv3 3x3/s2 BN ReLU, conv4 3x3 BN; conv5 1x1/s2 (x1);
            add ReLU                                                 -> x2   (32 ch, 16x16)
    stack3: conv6 3x3/s2 BN ReLU, conv7 3x3 BN; conv8 1x1/s2 (x2);
            add ReLU                                                 -> x3   (64 ch, 8x8)
    avgpool 8x8, dense 64->10 (softmax dropped: argmax only)

BatchNorm is folded into the preceding conv (eps 1e-3, Keras default).  Keras 'same'
padding is reproduced exactly: stride 1 pads 1 on every side, a 3x3 stride-2 conv on an
even input pads only right/bottom (total 1), a 1x1 stride-2 conv pads nothing.
Input: raw pixels 0..255 as float (the model was trained without normalisation).

    python -m nn.model.resnet8          # float accuracy on the CIFAR-10 test set
"""
import json

import h5py
import numpy as np
import torch
import torch.nn.functional as F

# (name, keras conv layer, keras BN layer or None, kernel, stride, cin, cout, relu)
CONVS = [
    ("conv0", "conv2d",   "batch_normalization",   3, 1, 3,  16, True),
    ("conv1", "conv2d_1", "batch_normalization_1", 3, 1, 16, 16, True),
    ("conv2", "conv2d_2", "batch_normalization_2", 3, 1, 16, 16, False),
    ("conv3", "conv2d_3", "batch_normalization_3", 3, 2, 16, 32, True),
    ("conv4", "conv2d_4", "batch_normalization_4", 3, 1, 32, 32, False),
    ("conv5", "conv2d_5", None,                    1, 2, 16, 32, False),
    ("conv6", "conv2d_6", "batch_normalization_5", 3, 2, 32, 64, True),
    ("conv7", "conv2d_7", "batch_normalization_6", 3, 1, 64, 64, False),
    ("conv8", "conv2d_8", None,                    1, 2, 32, 64, False),
]
CONV_CFG = {c[0]: c for c in CONVS}
BN_EPS = 1e-3


def keras_same_pad(x, k, s, value=0.0):
    """Pad NCHW x like Keras/TF 'same' (extra padding goes right/bottom)."""
    h = x.shape[-1]
    out = -(-h // s)
    total = max((out - 1) * s + k - h, 0)
    lo, hi = total // 2, total - total // 2
    return F.pad(x, (lo, hi, lo, hi), value=value)


def load_h5(path):
    """Return {conv name: (W[cout,cin,k,k], b[cout])} with BN folded, plus the dense layer."""
    f = h5py.File(path, "r")
    cfg = json.loads(f.attrs["model_config"])
    names = [l["config"]["name"] for l in cfg["config"]["layers"]]
    w = lambda layer, p: np.array(f["model_weights"][layer][layer][p + ":0"], dtype=np.float64)
    params = {}
    for name, kl, bnl, k, s, cin, cout, _ in CONVS:
        assert kl in names
        W = w(kl, "kernel").transpose(3, 2, 0, 1)            # (kh,kw,cin,cout) -> (cout,cin,kh,kw)
        b = w(kl, "bias")
        assert W.shape == (cout, cin, k, k)
        if bnl is not None:
            g, beta = w(bnl, "gamma"), w(bnl, "beta")
            mu, var = w(bnl, "moving_mean"), w(bnl, "moving_variance")
            sc = g / np.sqrt(var + BN_EPS)
            W = W * sc[:, None, None, None]
            b = (b - mu) * sc + beta
        params[name] = (W, b)
    params["fc"] = (w("dense", "kernel").T, w("dense", "bias"))  # (10, 64)
    return params


class ResNet8:
    """Float reference (BN folded), float64 by default.  forward() returns logits."""

    def __init__(self, params, dtype=torch.float64, device="cpu"):
        self.p = {k: (torch.tensor(W, dtype=dtype, device=device), torch.tensor(b, dtype=dtype, device=device))
                  for k, (W, b) in params.items()}
        self.dtype, self.device = dtype, device

    def conv(self, name, x):
        _, _, k, s, _, _, relu = CONV_CFG[name][1:]
        W, b = self.p[name]
        y = F.conv2d(keras_same_pad(x, k, s), W, b, stride=s)
        return F.relu(y) if relu else y

    def forward(self, x, taps=None):
        """x: NHWC uint8/float pixels.  taps: optional dict filled with every intermediate tensor."""
        t = taps if taps is not None else {}
        x = torch.as_tensor(x, device=self.device).to(self.dtype).permute(0, 3, 1, 2)
        t["conv0"] = x0 = self.conv("conv0", x)
        t["conv1"] = h = self.conv("conv1", x0)
        t["conv2"] = y = self.conv("conv2", h)
        t["add1"] = x1 = F.relu(x0 + y)
        t["conv3"] = h = self.conv("conv3", x1)
        t["conv4"] = y = self.conv("conv4", h)
        t["conv5"] = sc = self.conv("conv5", x1)
        t["add2"] = x2 = F.relu(sc + y)
        t["conv6"] = h = self.conv("conv6", x2)
        t["conv7"] = y = self.conv("conv7", h)
        t["conv8"] = sc = self.conv("conv8", x2)
        t["add3"] = x3 = F.relu(sc + y)
        t["pool"] = p = x3.mean(dim=(2, 3))
        W, b = self.p["fc"]
        t["fc"] = logits = p @ W.T + b
        return logits


def evaluate(fn, x, y, bs=1000):
    correct = 0
    for i in range(0, len(x), bs):
        correct += (fn(x[i:i + bs]).argmax(1).cpu().numpy() == y[i:i + bs]).sum()
    return correct / len(x)


if __name__ == "__main__":
    from .data import H5_PATH, test_set
    xt, yt = test_set()
    m = ResNet8(load_h5(H5_PATH))
    print(f"float ResNet-8 (BN folded) CIFAR-10 test accuracy: {100 * evaluate(m.forward, xt, yt):.2f} %")
