"""ResNet-8 (MLPerf Tiny) with QCConv2d convs; graph identical to nn/model/resnet8.py.

Every conv (incl. the conv5/conv8 1x1 shortcuts) is QCConv2d + BatchNorm (the BN is the allowed
per-channel scale + bias), ReLU where the baseline has one.  FC stays dense float.  Input: NHWC raw
pixels 0..255 (same convention as nn/).
"""
import torch
import torch.nn as nn
import torch.nn.functional as F

from nn.model.resnet8 import CONVS

from .layers import QCConv2d


class QCResNet8(nn.Module):
    def __init__(self, mode="unsigned", b=8, topk=2, view="hwc", method="staged", thr=0.0,
                 width=1):
        """b: int, list (one per conv in CONVS order) or {conv name: block size}.
        width: channel multiplier of every conv (conv0 input stays 3); capacity probe only, not ResNet-8."""
        super().__init__()
        if isinstance(b, (list, tuple)):
            assert len(b) == len(CONVS)
            b = {c[0]: bc for c, bc in zip(CONVS, b)}
        bs = b if isinstance(b, dict) else {c[0]: b for c in CONVS}
        w = lambda c: c if c == 3 else c * width
        self.conv = nn.ModuleDict({n: QCConv2d(w(cin), w(cout), k, s, bs[n], mode, topk, view, method, thr)
                                   for n, _, _, k, s, cin, cout, _ in CONVS})
        self.bn = nn.ModuleDict({n: nn.BatchNorm2d(w(cout)) for n, *_, cout, _ in CONVS})
        self.relu = {c[0]: c[7] for c in CONVS}
        self.fc = nn.Linear(64 * width, 10)

    def c(self, name, x):
        y = self.bn[name](self.conv[name](x))
        return F.relu(y) if self.relu[name] else y

    def forward(self, x):
        x = x.permute(0, 3, 1, 2).to(self.fc.weight.dtype)
        x0 = self.c("conv0", x)
        x1 = F.relu(x0 + self.c("conv2", self.c("conv1", x0)))
        x2 = F.relu(self.c("conv5", x1) + self.c("conv4", self.c("conv3", x1)))
        x3 = F.relu(self.c("conv8", x2) + self.c("conv7", self.c("conv6", x2)))
        return self.fc(x3.mean(dim=(2, 3)))
